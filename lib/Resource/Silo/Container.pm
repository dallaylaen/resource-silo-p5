package Resource::Silo::Container;

use strict;
use warnings;

=head1 NAME

Resource::Silo::Container - base resource storage class for L<Resource::Silo>.

=head1 DESCRIPTION

=head1 METHODS

=cut

use Carp;
use Scalar::Util qw(reftype);

use Resource::Silo::Controller;

our @CARP_NOT = qw(Resource::Silo Resource::Silo::Spec);

=head2 new

=cut

sub new {
    my ($class, %stubs) = @_;
    my $self = bless {
        pid  => $$,
        spec => $class->metadata,
    }, $class;
    foreach (keys %stubs) {
        $self->{rw_cache}{$_} = $stubs{$_};
    };
    return $self;
};

=head2 C<ctl>

Interface to control methods.

=cut

sub ctl {
    return Resource::Silo::Controller->new(shift);
};

=head2 fetch( $resource_name )

Fetch resource, lazily initializing it.

Typically C<silo-E<gt>foo> will call C<silo-E<gt>fetch("foo")> internally.

=cut

sub fetch {
    my ($self, $name, $arg) = @_;

    # Determine resource key ASAP
    my $key = $name . (defined $arg && !ref $arg? "\@$arg" : '');

    # If there was a fork, flush cache
    if ($self->{pid} != $$) {
        delete $self->{rw_cache};
        $self->{pid} = $$;
    };

    # Return from cache (most common case), do sanity checks later
    return $self->{rw_cache}{$key} //= do {
        my $spec = $self->{spec}->spec($name);

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
};

=head2 cached( $resource_name )

Return cached resource without initializing.

=cut

sub cached {
    my ($self, $name) = @_;
    return $self->{rw_cache}{$name};
};


1;
