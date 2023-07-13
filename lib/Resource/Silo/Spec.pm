package Resource::Silo::Spec;

use strict;
use warnings;

=head1 NAME

Resource::Silo::Spec - description of known resource types for L<Resource::Silo>

=head1 METHODS

=cut

use Carp;
use Scalar::Util qw(reftype);

our @CARP_NOT = qw(Resource::Silo Resource::Silo::Container);

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

my %known_args = (
    init      => 1,
    argument  => 1,
);
sub add {
    my $self = shift;
    my $name = shift;
    if (@_ % 2) {
        my $init = pop @_;
        unshift @_, init => $init;
    }
    my (%spec) = @_;

    my @extra = grep { !$known_args{$_} } keys %spec;
    croak "resource: unknown arguments in specification: @extra"
        if @extra;

    croak "resource: init must be a function"
        unless $spec{init} and reftype $spec{init} eq 'CODE';

    if (!defined $spec{argument}) {
        # do nothing
    } elsif ((reftype $spec{argument} // '') eq 'REGEXP') {
        my $rex = qr(^(?:$spec{argument})$);
        $spec{argument} = sub { $_[0] =~ $rex };
    } elsif ((reftype $spec{argument} // '') eq 'CODE') {
        # do nothing, we're fine
    } else {
        croak "resource: argument must be a regexp or function";
    }

    $self->{spec}{$name} = \%spec;

    {
        my $method = sub { $_[0]->fetch( $name, $_[1] ) };

        no strict 'refs'; ## no critic Strictures
        *{"$self->{target}::$name"} = $method;
    }

    return $self;
};

=head2 spec

Fetch specifications for given resource.

=cut

# TODO name!!!
sub spec {
    my ($self, $name) = @_;
    return $self->{spec}{$name};
};

1;
