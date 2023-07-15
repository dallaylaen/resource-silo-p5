package Resource::Silo::Spec;

use strict;
use warnings;

=head1 NAME

Resource::Silo::Spec - description of known resource types for L<Resource::Silo>

=head1 METHODS

=cut

use Carp;
use Scalar::Util qw(reftype);

=head2 new( $target )

$target is the name of the module where resource access methods will be created.

=cut

sub new {
    my ($class, $target) = @_;
    return bless { target => $target }, $class;
};

=head2 add( $resource_name, ... )

Create resource type. See L<Resource::Silo/resource> for details.

=cut

my %known_args = (
    init        => 1,
    argument    => 1,
    ignore_lock => 1,
);
sub add {
    my $self = shift;
    my $name = shift;
    if (@_ % 2) {
        my $init = pop @_;
        unshift @_, init => $init;
    }
    my (%spec) = @_;
    my $target = $self->{target};

    croak "resource: name must be an identifier"
        unless defined $name and !ref $name and $name =~ /^[a-z][a-z_0-9]*/i;
    croak "resource: attempt to redefine resource '$name'"
        if $self->spec($name);
    croak "resource: attempt to replace existing method in $target"
        if $target->can($name);

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

    # Move code generation into Resource::Silo::Instance
    # so that exceptions via croak() are attributed correctly.
    {
        no strict 'refs'; ## no critic Strictures
        *{"${target}::$name"} =
            Resource::Silo::Instance::_make_resource_accessor($name, \%spec);
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

=head2 generate_dsl

Create C<resource> function closed over current object.

=cut

# TODO name!!
sub generate_dsl {
    my $inst = shift;
    return sub { $inst->add(@_) };
};

1;
