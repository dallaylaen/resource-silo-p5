package Resource::Silo::Spec;

use strict;
use warnings;

=head1 NAME

Resource::Silo::Spec - description of known resource types for L<Resource::Silo>

=head1 METHODS

=cut


=head2 new

No parameters yet.

=cut

sub new {
    my $class = shift;
    return bless {}, $class;
};

=head2 add( $resource_name, ... )

Create resource type.

=cut

sub add {
    my ($self, $name, $init) = @_;

    # TODO allow more args

    $self->{init}{$name} = $init;
    return $self;
};

=head2 init

Fetch initialization sub for given resource.

=cut

sub init {
    my ($self, $name) = @_;
    return $self->{init}{$name};
};

1;
