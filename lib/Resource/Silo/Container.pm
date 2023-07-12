package Resource::Silo::Container;

use strict;
use warnings;

=head1 NAME

Resource::Silo::Container - base resource storage class for L<Resource::Silo>.

=head1 DESCRIPTION

=head1 METHODS

=cut

use Carp;

=head2 new

=cut

sub new {
    my ($class, $spec) = @_;
    my $self = {
        pid  => $$,
        spec => $spec,
    };
    return bless $self, $class;
};

=head2 fetch( $resource_name )

Fetch resource, lazily initializing it.

Typically C<silo-E<gt>foo> will call C<silo-E<gt>fetch("foo")> internally.

=cut

sub fetch {
    my ($self, $name, $arg) = @_;
    # TODO arg unused

    if ($self->{pid} != $$) {
        delete $self->{rw_cache};
        $self->{pid} = $$;
    };

    return $self->{rw_cache}{$name} //= do {
        $self->{spec}->init($name)->($self, $name);
    };
};

=head2 cached( $resource_name )

Return cached resource without initializing.

=cut

sub cached {
    my ($self, $name) = @_;
    return $self->{rw_cache}{$name};
};



1;
