package Resource::Silo::Instance;

use strict;
use warnings;

=head1 NAME

Resource::Silo::Instance - base resource container class for L<Resource::Silo>.

=head1 DESCRIPTION

L<Resource::Silo> isolates resources by storing them
inside a container object.

The methods of such an object are generated on the fly and stored either
in a special virtual package, or the calling module.

This class provides some common functionality that allows to access resources,
as well as a doorway into a fine-grained control interface.

=head1 METHODS

=cut

use Carp;
use Scalar::Util qw( blessed reftype weaken );

my $ID_REX = qr/^[a-z][a-z_0-9]*$/i;

=head2 new( resource => $override, ... )

Create a new container (also available as C<silo-E<gt>new>).

If arguments are given, they will be passed to the
L</override> method (see below).

=cut

# NOTE to the editor. As we want to stay compatible with Moo/Moose,
# please make sure all internal fields start with a hyphen ("-").

sub new {
    my $class = shift;
    $class = ref $class if blessed $class;
    my $self = bless {
        -pid  => $$,
        -spec => $class->metadata,
    }, $class;
    $self->ctl->override( @_ )
        if @_;
    return $self;
};

sub DESTROY {
    my $self = shift;
    $self->ctl->cleanup;
};

# Instantiate resource $name with argument $argument.
# This is what a silo->resource_name calls after checking the cache.
sub _instantiate_resource {
    my ($self, $name, $arg) = @_;

    croak "Illegal resource name '$name'"
        unless $name =~ $ID_REX;

    my $spec = $self->{-spec}->spec($name);
    $arg //= '';

    croak "Attempting to fetch nonexistent resource $name"
        unless $spec;
    croak "Argument for resource '$name' must be a scalar"
        if ref $arg;
    croak "Illegal argument for resource '$name': '$arg'"
        unless $spec->{argument}->($arg);

    croak "Attempting to initialize resource in destructor"
        if $self->{-cleanup};
    croak "Attempting to initialize resource '$name' in locked mode"
        if $self->{-locked}
            and !$spec->{assume_pure}
            and !$self->{-override}{$name};

    # Detect circular dependencies
    my $key = $name . (length $arg ? "\@$arg" : '');
    if ($self->{-pending}{$key}) {
        my $loop = join ', ', sort keys %{ $self->{-pending} };
        croak "Circular dependency detected for resource $key: {$loop}";
    };
    local $self->{-pending}{$key} = 1;

    ($self->{-override}{$name} || $spec->{init})->($self, $name, $arg);
};

# use instead of delete $self->{-cache}{$name}
sub _cleanup_resource {
    my ($self, $name, @list) = @_;

    # TODO Do we need to validate arguments here?
    my $action = $self->{-override}{$name}
        ? undef
        : $self->{-spec}{$name}{cleanup};
    my $known = $self->{-cache}{$name};

    @list = keys %$known
        unless @list;

    foreach my $arg (@list) {
        $arg //= '';
        next unless defined $known->{$arg};
        $action->($known->{$arg}) if $action;
        delete $known->{$arg};
    };
};

# We must create resource accessors in this package
#   so that errors get attributed correctly
#   (+ This way no other class need to know our internal structure)
sub _make_resource_accessor {
    my ($name, $spec) = @_;

    if ($spec->{ignore_cache}) {
        return sub {
            my ($self, $arg) = @_;
            return $self->_instantiate_resource($name, $arg);
        };
    };

    return sub {
        my ($self, $arg) = @_;

        # If there was a fork, flush cache
        if ($self->{-pid} != $$) {
            # TODO invent some post-fork cleanup - but not now
            delete $self->{-cache};
            $self->{-pid} = $$;
        };

        # Stringify $arg ASAP, we'll validate it inside _instantiate_resource().
        # The cache entry for an invalid argument will never get populated.
        my $key = defined $arg && !ref $arg ? $arg : '';
        $self->{-cache}{$name}{$key} //= $self->_instantiate_resource($name, $arg);
    };
};

=head1 CONTROL INTERFACE

Sometimes more fine-grained control over the container is needed than just
fetching the resources.

Since the container class can contain arbitrary resource names and
some user-defined methods to boot, instead of polluting its namespace,
we provide a single method, C<ctl>, that returns a temporary facade object
that provide access to the following methods.

Most of them return the facade so that they can be chained. E.g.

    # somewhere in your tests
    silo->ctl->lock->override(
        config  => { ... },     # some fixed values
        dbh     => sub { ... }, # return SQLite instance
    );

=head2 C<ctl>

Returns the facade.

B<NOTE> the facade object is weak reference to the parent object
and thus must not be save anywhere, lest you be surprised.
Use it and discard immediately.

=cut

sub ctl {
    my $self = shift;
    my $facade = bless \$self, 'Resource::Silo::Control';
    weaken $$facade;
    confess "Attempt to close over nonexistent value"
        unless $$facade;
    return $facade;
};

# We're declaring a different package in the same file because
# 1) it must have access to the internals anyway and
# 2) we want to keep the documentation close to the implementation.
package
    Resource::Silo::Control;

use Carp;
use Scalar::Util qw( reftype );

=head2 override( %substitutes )

Provide a set of overrides for some of the resources.

This can be used e.g. in tests to mock certain external facilities.

%substitutes values are interpreted as follows:

=over

=item * C<sub { ... }> - use this code instead of the resource's C<init>;

=item * C<undef> - erase the override for given resource;

=item * anything else is coerced into an initializer:
$value => sub { return $value }.

=back

Setting overrides has the side effect of clearing cache
for the affected resources.

=cut

sub override {
    my ($self, %subst) = @_;

    foreach my $name (keys %subst) {
        croak "Illegal resource name '$name'"
            unless $name =~ $ID_REX;
        croak "Attempt to override unknown resource $name"
            unless $$self->{-spec}{$name};
        my $init = $subst{$name};

        # Finalize existing values in cache, just in case
        # BEFORE setting up override
        $$self->_cleanup_resource($name);

        if (defined $init) {
            $$self->{-override}{$name} = (reftype $init // '') eq 'CODE'
                ? $init
                : sub { $init };
        } else {
            delete $$self->{-override}{$name};
        };
    };

    return $self;
}

=head2 lock

Forbid initializing new resources.

The cached ones instantiated so far, the ones that have been overridden,
and the ones with the C<assume_pure> flag will still be returned.

=cut

sub lock {
    my ($self) = @_;
    $$self->{-locked} = 1;
    return $self;
};

=head2 unlock

Remove the lock set by C<lock>.

=cut

sub unlock {
    my $self = shift;
    delete $$self->{-locked};
    return $self;
};

=head2 preload()

Try loading all the resources that have C<preload> flag set.

May be useful if e.g. a server-side application is starting and must
check its database connection(s) before it starts handling any clients.

=cut

sub preload {
    my $self = shift;
    # TODO allow specifying resources to load
    #      but first come up with a way of specifying arguments, too.

    my $list = $$self->{-spec}{-preload};
    for my $name (@$list) {
        my $unused = $$self->$name;
    };
    return $self;
};

=head2 cleanup

Cleanup all resources.
Once the cleanup is started, no more resources can be created,
and trying to do so will result in exception.
Typically only useful for destruction.

=cut

sub cleanup {
    my $self = ${ $_[0] };
    $self->{-cleanup} = 1; # This is stronger than lock.

    my $spec = $self->{-spec};
    my @order = sort {
        $spec->{$a}{cleanup_delay} <=> $spec->{$b}{cleanup_delay};
    } keys %{ $self->{-cache} };

    foreach my $name (@order) {
        $self->_cleanup_resource($name);
    };

    delete $self->{-cache};
    return $_[0];
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
    return ${+shift}->_instantiate_resource(@_);
};

1;
