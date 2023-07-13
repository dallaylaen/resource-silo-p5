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
    my ($class, $target) = @_;
    return bless { target => $target }, $class;
};

=head2 add( $resource_name, ... )

Create resource type.

=cut

sub add {
    my ($self, $name, $init) = @_;

    # TODO allow more args

    $self->{init}{$name} = $init;

    {
        no strict 'refs'; ## no critic Strictures
        *{"$self->{target}::$name"} = sub { $_[0]->fetch( $name ) };
    }
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
