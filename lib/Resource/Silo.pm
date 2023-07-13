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

=head2 resource 'name' => sub { ... };

=cut

use Carp;
use Exporter;

use Resource::Silo::Spec;
use Resource::Silo::Container;

sub import {
    my $target = caller;
    my @export = qw(silo);

    my $spec = Resource::Silo::Spec->new($target);

    my $resource = sub {
        my ($name, $init) = @_;
        $spec->add($name, $init);
    };

    my $instance;
    my $silo = sub () { ## no critic 'prototypes'
        return $instance //= $target->new();
    };

    no strict 'refs'; ## no critic
    no warnings 'redefine', 'once'; ## no critic

    push @{"${target}::ISA"}, 'Resource::Silo::Container', 'Exporter';
    push @{"${target}::EXPORT"}, qw(silo);
    *{"${target}::metadata"} = sub { $spec };
    *{"${target}::resource"} = $resource;
    *{"${target}::silo"}     = $silo;
};

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
