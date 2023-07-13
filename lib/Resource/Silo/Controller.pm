package Resource::Silo::Controller;

use strict;
use warnings;

=head1 NAME

Resource::Silo::Controller - a facade to L<Resource::Silo> instance control methods.

=head1 DESCRIPTION

As L<Resource::Silo::Instance> is supposed to be inherited by the calling code,
we cannot ensure that method names never clash. Therefore, we provide a single
C<ctl> method that in turn provides access to instance lifecycle and management
methods without polluting the common namespace.

=cut

use Carp;
use Scalar::Util qw(weaken reftype);

=head2 new( $the_real_thing )

Create a frontend for $the_real_thing.

B<NOTE> This class ignores class boundaries whatsoever and modifies content
of the thing it refers to directly. It also holds a weak reference
and thus should not be saved anywhere or everything goes boom.

=cut

sub new {
    my ($class, $ref) = @_;
    # Dumb facade
    my $self = bless \$ref, $class;
    weaken $$self;
    confess "Attempt to close over a null reference"
        unless $$self;
    return $self;
};

=head2 override( name => sub { ... }, ... )

Provide a set of overrides for some of the resources.

This can be used e.g. in tests to mock certain external facilities.

If provided value is not a subroutine reference, it will be coerced into
a constant one returning the given value: C<name =E<gt> sub { $value };>

=cut

sub override {
    my ($self, %subst) = @_;

    foreach my $name (keys %subst) {
        croak "Attempt to override unknown resource $name"
            unless $$self->{spec}->spec($name);
        my $init = $subst{$name};
        $$self->{override}{$name} = (reftype $init // '') eq 'CODE'
            ? $init
            : sub { $init };
    };

    return $self;
}

=head2 clear_overrides

Remove all overrides set by C<override> call(s).

=cut

sub clear_overrides {
    my $self = shift;
    delete $$self->{override};
    return $self;
};

=head2 lock

Forbid initializing new resources.

The cached ones instantiated so far, the ones that have been overridden,
and the ones with the C<ignore_lock> flag will still be returned.

=cut

sub lock {
    my ($self) = @_;
    $$self->{locked} = 1;
    return $self;
};

=head2 unlock

Remove the lock set by C<lock>.

=cut

sub unlock {
    my $self = shift;
    delete $$self->{locked};
    return $self;
};

=head2 clean_cache

Remove all cached resources.

No cleanup is called whatsoever, but it may be added in the future.

=cut

sub clean_cache {
    my $self = shift;
    delete $$self->{rw_cache};
    return $self;
};

1;
