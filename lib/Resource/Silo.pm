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

=item   (i) All available resources are declared in a single module.

=item  (ii) Such module is equipped with methods to access resources,
as well as an exportable prototyped function for obtaining the one and true
instance of it (AKA optional singleton).

=item (iii) Every class or script in the project accesses resources
through this module and only through it.

=back

=head1 SYNOPSIS

    # in the resource module
    package My::Project;

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
    1;

    # elsewhere in modules or scripts
    use My::Project qw(silo);

    my $statement = silo->dbh->prepare( $sql );
    my $queue = silo->queue;


=head1 EXPORT

Upon using Resource::Silo in your module, a number of things happen:

=over

=item * L<Resource::Silo::Container> and L<Exporter> are added to C<@ISA>;

=item * a C<silo> function returning the "default" calling package instance
(obtained via new()) is created and added to C<@EXPORT>;

=item * a C<metadata> function/method returning
a static L<Resource::Silo::Spec> object is created;

=item * a C<resource> function is created that can be used to define resources.

=back

=head2 silo

silo() always returns the same object, creating it if necessary.

This is how other modules in the project are supposed to access the resources:

    # in My::Project::Some::Module
    use My::Project::Resources;
    silo->dbh; # returns a database handler defined in My::Project::Resources

=head2 metadata

Returns a static L<Resource::Silo::Spec> object associated with this package.

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

=item * ignore_lock => 1 | 0

Allow initializing resource, even when the resource container is put into
locked mode.

For example, if resource is derived from other resources, its creation
may be safe as long as the dependencies have been mocked
or already instantiated.

(See the above example with L<Redis::Namespace>).

=back

=cut

use Carp;
use Exporter;

use Resource::Silo::Spec;
use Resource::Silo::Container;

# Must enforce correctly freeing the resources, closing connections etc
# before program ends.
my @todestroy;
END {
    $_->ctl->clean_cache
        foreach @todestroy;
};

sub import {
    my $target = caller;
    my @export = qw(silo);

    my $spec = Resource::Silo::Spec->new($target);

    # Eh? somehow this works without a prototype, so be it.
    my $resource = sub {
        $spec->add(@_);
    };

    my $instance;
    my $silo = sub {
        unless (defined $instance) {
            $instance = $target->new;
            push @todestroy, $instance;
        };
        return $instance;
    };

    no strict 'refs'; ## no critic
    no warnings 'redefine', 'once'; ## no critic

    push @{"${target}::ISA"}, 'Resource::Silo::Container', 'Exporter';
    push @{"${target}::EXPORT"}, qw(silo);
    *{"${target}::metadata"} = sub { $spec };
    *{"${target}::resource"} = $resource;
    *{"${target}::silo"}     = $silo;
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

The C<lock>/C<unlock> methods in L<Resource::Silo::Controller>,
available via C<silo-E<gt>ctl> frontend,
temporarily forbid instantiating new resources.
The resources already in cache will still be OK though.

The C<override> method allows to supply substitutes for resources or
their initializers.

The C<ignore_lock> flag in the resource definition may be used to indicate
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

See L<Resource::Silo::Container> for resource container implementation.
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
