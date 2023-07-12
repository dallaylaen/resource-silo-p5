package Resource::Silo;

use 5.006;
use strict;
use warnings;

=head1 NAME

Resource::Silo - The great new Resource::Silo!

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use Resource::Silo;

    my $foo = Resource::Silo->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=cut

use Exporter;
use Carp;

use Resource::Silo::Spec;
use Resource::Silo::Container;

sub import {
    my $class = caller;
    my @export = qw(silo);

    my $spec = Resource::Silo::Spec->new;

    my $resource = sub {
        my ($name, $init) = @_;
        $spec->add($name, $init);
        no strict 'refs'; ## no critic
        *{"${class}::$name"} = sub { $_[0]->fetch($name) };
    };

    my $instance;
    my $silo = sub {
        return $instance //= $class->new($spec);
    };

    my $import = sub {
        my $class = caller;
        no strict 'refs'; ## no critic
        *{"${class}::silo"} = $silo;
    };

    no strict 'refs'; ## no critic
    no warnings 'redefine', 'once'; ## no critic

    @{"${class}::ISA"} = 'Resource::Silo::Container';
    *{"${class}::metadata"} = $spec;
    *{"${class}::import"} = $import;
    *{"${class}::resource"} = $resource;
};

=head1 AUTHOR

Konstantin Uvarin, C<< <khedin@gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-Resource-Silo at rt.cpan.org>, or through
the web interface at L<https://rt.cpan.org/NoAuth/ReportBug.html?Queue=Resource-Silo>.




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


=head1 LICENSE AND COPYRIGHT

This software is free software.

Copyright (c) 2022 by Konstantin Uvarin.

=cut

1; # End of Resource::Silo
