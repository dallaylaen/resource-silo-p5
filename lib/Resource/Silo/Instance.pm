package Resource::Silo::Instance;

use strict;
use warnings;

=head1 NAME

Resource::Silo::Instance - base resource storage class for L<Resource::Silo>.

=head1 DESCRIPTION

=head1 METHODS

=cut

use Carp;
use Scalar::Util qw(reftype blessed);

use Resource::Silo::Control;

=head2 new

=cut

sub new {
    my $class = shift;
    $class = ref $class if blessed $class;
    my $self = bless {
        pid  => $$,
        spec => $class->metadata,
    }, $class;
    $self->ctl->override( @_ )
        if @_;
    return $self;
};

=head2 C<ctl>

Interface to control methods.

=cut

sub ctl {
    return Resource::Silo::Control->new(shift);
};

=head2 fresh( $resource_name [, $argument ] )

Instantiate resource and return it, ignoring cached value, if any.
This may be useful if the resource's state is going to be modified
in a manner incompatible with its other consumers within the same process.

E.g. performing a Big Evil SQL Transaction while other parts of the application
are happily using L<DBIx::Class>.

B<NOTE> Use with caution.
Resorting to this method frequently may be a sign of a broader
architectural problem.

=cut

sub fresh {
    my ($self, $name, $arg) = @_;
    my $spec = $self->{spec}->spec($name);
    $arg //= '';

    croak "Attempting to fetch nonexistent resource $name"
        unless $spec;
    croak "Argument for resource '$name' must be a scalar"
        if ref $arg;
    croak "Argument check failed for resource '$name': '$arg'"
        unless $spec->{argument}->($arg);

    croak "Attempting to initialize resource '$name' in locked mode"
        if $self->{locked}
            and !$spec->{assume_pure}
            and !$self->{override}{$name};

    # Detect circular dependencies
    my $key = $name . (length $arg ? "\@$arg" : '');
    if ($self->{pending}{$key}) {
        my $loop = join ', ', sort keys %{ $self->{pending} };
        croak "Circular dependency detected for resource $key: {$loop}";
    };
    local $self->{pending}{$key} = 1;

    ($self->{override}{$name} || $spec->{init})->($self, $name, $arg);
};

=head2 cached( $resource_name )

Return cached resource without initializing.

=cut

# TODO move to Control, handle args
sub cached {
    my ($self, $name) = @_;
    return $self->{rw_cache}{$name}{''};
};

# We must create resource accessors in this package
#   so that errors get attributed correctly
#   (+ This way no other class need to know our internal structure)
sub _make_resource_accessor {
    my ($name, $spec) = @_;

    if ($spec->{ignore_cache}) {
        return sub {
            my ($self, $arg) = @_;
            return $self->fresh($name, $arg);
        };
    };

    return sub {
        my ($self, $arg) = @_;

        # If there was a fork, flush cache
        if ($self->{pid} != $$) {
            delete $self->{rw_cache};
            $self->{pid} = $$;
        };

        # Stringify $arg ASAP, we'll validate it inside fresh().
        # The cache entry for an invalid argument will never get populated.
        my $key = defined $arg && !ref $arg ? $arg : '';
        $self->{rw_cache}{$name}{$key} //= $self->fresh($name, $arg);
    };
};

1;
