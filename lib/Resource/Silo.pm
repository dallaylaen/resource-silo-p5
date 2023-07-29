package Resource::Silo;

use 5.010;
use strict;
use warnings;

our $VERSION = 0.01;

=head1 NAME

Resource::Silo - lazy declarative resource management for Perl.

=head1 DESCRIPTION

We assume the following setup:

=over

=item   (i) The application needs to access multiple resources, such as
configuration files, databases, queues, service endpoints, credentials, etc.

=item  (ii) The application has helper scripts that don't need to initialize
all the resources at once, as well as a test suite where accessing resources
is undesirable unless a fixture or mock is provided.

=item (iii) The resource management has to be decoupled from the application
logic where possible.

=back

And we propose the following solution:

=over

=item   (i) All available resources are declared in one place
and encapsulated within a single container.

=item  (ii) Such container is equipped with methods to access resources,
as well as an exportable prototyped function for obtaining the one and true
instance of it (AKA optional singleton).

=item (iii) Every class or script in the project accesses resources
through this container and only through it.

=back

=head1 SYNOPSIS

The default mode is to create a one-off container for all resources
and export if into the calling class via C<silo> function.

Note that calling C<use Resource::Silo> from a different module will
create a I<separate> container instance, but see below.

    package My::App;
    use Resource::Silo;

    use DBI;
    use YAML::LoadFile;
    ...

    resource config => sub { LoadFile( ... ) };
    resource dbh    => sub {
        my $self = shift;
        my $conf = $self->config->{dbh};
        DBI->connect( $conf->{dsn}, $conf->{user}, $conf->{pass}, { RaiseError => 1 } );
    };
    resource queue  => sub { My::Queue->new( ... ) };
    ...

    my $statement = silo->dbh->prepare( $sql );
    my $queue = silo->queue;

For more complicated projects, it may make sense
to create a dedicated class for resource management:

    # in the container class
    package My::Project::Res;
    use Resource::Silo -class;      # resource definitions will now create
                                    # eponymous methods in My::Project::Res

    resource foo => sub { ... };    # declare resources as in the above example
    resource bar => sub { ... };

    1;

    # in all other modules/packages/scripts:

    package My::Project;
    use My::Project::Res qw(silo);

    silo->foo;                      # obtain resources
    silo->bar;

    My::Project::Res->new;          # separate empty resource container

=head1 EXPORT

The following functions will be exported into the calling module,
unconditionally:

=over

=item * silo - a singleton function returning the resource container.
Note that this function will be created separately for every calling module,
and needs to be re-exported to be shared.

=item * resource - a DSL for defining resources, their initialization
and properties. See below.

=back

Additionally, if the C<-class> argument was added to the use line,
the following things happen:

=over

=item * L<Resource::Silo::Instance> and L<Exporter> are added to C<@ISA>;

=item * C<silo> function is added to C<@EXPORT> and thus becomes re-exported
by default;

=item * a C<metadata> function/method returning
a static L<Resource::Silo::Spec> object is created;

=item * calling C<resource> creates a corresponding method in this package.

=back

=head1 RESOURCE DEFINITION

=head2 resource

    resource 'name' => sub { ... };
    resource 'name' => %options;

Define a resource.

%options may include:

=over

=item * init => sub { $self, $name, [$argument] }

A coderef to obtain the resource. Required.

If the number of arguments is odd,
the last one is shifted and considered to be the init function.

=item * argument => C<sub { ... }> || C<qr( ... )>

A sanity check on a string argument for the resource fetching function.

If specified, the argument must always be supplied, the regular expression
must match I<the whole> string, and the function return a true value.
Otherwise an exception will be raised.

Example:

    use Resource::Silo;
    use Redis;
    use Redis::Namespace;

    resource real_redis => sub { Redis->new };

    my %known_namespaces = (
        users    => 1,
        sessions => 1,
        counters => 1,
    );

    resource redis => argument => sub { $known_namespaces{ +shift } },
        init => sub {
            my ($self, $name, $ns) = @_;
            Redis::Namespace->new(
                redis     => $self->real_redis,
                namespace => $ns,
            );
        };

=item * assume_pure => 1 | 0

Assume that the resource introduces no new side effects
relative to its dependencies.
(Like in the above example with L<Redis::Namespace>).

Or, for instance, a L<DBIx::Class> database schema is probably safe
relative to the underlying L<DBI> handle.

B<EFFECT:> This will allow initializing resource,
even when the resource container is put into locked mode.
See L<Resource::Silo::Control/lock>.

=item * ignore_cache => 1 | 0

If set, don't cache resource, always create a fresh one instead.
See also L<Resource::Silo::Instance/fresh>.

=item * preload => 1 | 0

If set, try loading the resource when C<silo-E<gt>ctl-E<gt>preload> is called.

=back

=cut

use Carp;
use Exporter;
use Scalar::Util qw( set_prototype );

use Resource::Silo::Spec;
use Resource::Silo::Instance;

# Must enforce correctly freeing the resources, closing connections etc
# before program ends.
my @todestroy;
END {
    $_->ctl->clean_cache
        foreach @todestroy;
};


sub import {
    my ($self, @param) = @_;
    my $caller = caller;
    my $target;

    while (@param) {
        my $flag = shift @param;
        if ($flag eq '-class') {
            $target = $caller;
        } else {
            # TODO if there's more than 3 elsifs, use jump table instead
            croak "Unexpected parameter to 'use $self': '$flag'";
        };
    };

    $target ||= __PACKAGE__."::container::".$caller;

    my $spec = Resource::Silo::Spec->new($target);

    my $instance;
    my $silo = set_prototype {
        unless (defined $instance) {
            $instance = $target->new;
            push @todestroy, $instance;
        };
        return $instance;
    } '';

    no strict 'refs'; ## no critic
    no warnings 'redefine', 'once'; ## no critic

    push @{"${target}::ISA"}, 'Resource::Silo::Instance';
    *{"${target}::metadata"} = set_prototype { $spec } '';

    push @{"${caller}::ISA"}, 'Exporter';
    push @{"${caller}::EXPORT"}, qw(silo);
    *{"${caller}::resource"} = $spec->generate_dsl;
    *{"${caller}::silo"}     = $silo;
};


=head1 TESTING: LOCK AND OVERRIDES

It's usually a bad idea to access real-world resources in one's test suite,
especially if it's e.g. a partner's endpoint.

Now the #1 rule when it comes to mocks is to avoid mocks and instead design
the modules in such a way that they can be tested in isolation.
This however may not always be easily achievable.

Thus, L<Resource::Silo> provides a mechanism to substitute a subset of resources
with mocks and forbid the instantiation of the rest, thereby guarding against
unwanted side-effects.

The C<lock>/C<unlock> methods in L<Resource::Silo::Control>,
available via C<silo-E<gt>ctl> frontend,
temporarily forbid instantiating new resources.
The resources already in cache will still be OK though.

The C<override> method allows to supply substitutes for resources or
their initializers.

The C<assume_pure> flag in the resource definition may be used to indicate
that a resource is safe to instantiate as long as its dependencies are
either instantiated or mocked, e.g. a L<DBIx::Class> schema is probably fine
as long as the underlying database connection is taken care of.

Here is an example:

    use Test::More;
    use My::Project qw(silo);
    silo->ctl->lock->override(
        dbh => DBI->connect( 'dbi:SQLite:database=:memory:', '', '', { RaiseError => 1 ),
    );

    silo->dbh;                   # a mocked database
    silo->schema;                # a DBIx::Class schema reliant on the dbh
    silo->endpoint( 'partner' ); # an exception as endpoint wasn't mocked

=head1 CAVEATS AND CONSIDERATIONS

See L<Resource::Silo::Instance> for resource container implementation.
As of current, it is probably a bad idea to use L<Moose> on the same class
as L<Resource::Silo>.

=head2 CACHING

All resources are cached, the ones with arguments are cached together
with the argument.

=head2 FORKING

If the process forks, resources such as database handles may become invalid
or interfere with other processes' copies.
As of current, if a change in the process ID is detected,
the resource cache is erased altogether.

This may changed in the future as some resources
(e.g. configuration or endpoints) are stateless and don't require such checks.

=head2 CIRCULAR DEPENDENCIES

If a resource depends on other resources,
those will be simply created upon request.

It is possible to make several resources depend on each other.
Trying to initialize such resource will cause an expection, however.

=head1 BUGS

Please report any bugs or feature requests to
L<https://github.com/dallaylaen/resource-silo-p5/issues>
or via RT:
L<https://rt.cpan.org/NoAuth/ReportBug.html?Queue=Resource-Silo>.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Resource::Silo


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<https://rt.cpan.org/NoAuth/Bugs.html?Dist=Resource-Silo>

=item * CPAN Ratings

L<https://cpanratings.perl.org/d/Resource-Silo>

=item * Search CPAN

L<https://metacpan.org/release/Resource-Silo>

=back


=head1 ACKNOWLEDGEMENTS

The module was names after a building in game Heroes of Might and Magic III.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2023, Konstantin Uvarin, C<< <khedin@gmail.com> >>

This software is free software.
It is available on the same license terms as Perl itself.

=cut

1; # End of Resource::Silo
