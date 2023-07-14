package Resource::Silo::Instance;

use strict;
use warnings;

=head1 NAME

Resource::Silo::Instance - base resource storage class for L<Resource::Silo>.

=head1 DESCRIPTION

=head1 METHODS

=cut

use Carp;
use Scalar::Util qw(reftype);

use Resource::Silo::Control;

=head2 new

=cut

sub new {
    my $class = shift;
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

=head2 fetch( $resource_name )

Fetch resource, lazily initializing it.

Typically C<silo-E<gt>foo> will call C<silo-E<gt>fetch("foo")> internally.

=cut

sub fetch {
    my ($self, $name, $arg) = @_;

    # If there was a fork, flush cache
    if ($self->{pid} != $$) {
        delete $self->{rw_cache};
        $self->{pid} = $$;
    };

    # Replace everything but strings with '';
    #    we'll validate $arg later
    my $key = defined $arg && !ref $arg ? $arg : '';

    # Return from cache (most common case), do sanity checks later
    return $self->{rw_cache}{$name}{$key} //= $self->fresh( $name, $arg );
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
    my $key = $name . (defined $arg && !ref $arg? "\@$arg" : '');

    croak "Attempting to fetch nonexistent resource $name"
        unless $spec;

    if (my $check = $spec->{argument}) {
        croak "Argument required for resource '$name'"
            unless defined $arg;
        croak "Argument for resource '$name' must be a scalar"
            if ref $arg;
        croak "Argument check failed for resource '$name': $arg"
            unless $check->($arg);
    } else {
        croak "Argument not supported for resource '$name'"
            if defined $arg;
    };

    croak "Attempting to initialize resource '$name' in locked mode"
        if $self->{locked}
            and !$spec->{ignore_lock}
            and !$self->{override}{$name};

    # Detect circular dependencies
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

1;
