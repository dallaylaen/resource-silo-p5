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

# Instantiate resource $name with argument $argument.
# This is what a silo->resource_name calls after checking the cache.
sub _instantiate_resource {
    my ($self, $name, $arg) = @_;
    my $spec = $self->{-spec}->spec($name);
    $arg //= '';

    croak "Attempting to fetch nonexistent resource $name"
        unless $spec;
    croak "Argument for resource '$name' must be a scalar"
        if ref $arg;
    croak "Argument check failed for resource '$name': '$arg'"
        unless $spec->{argument}->($arg);

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
            unless $$self->{-spec}->spec($name);
        my $init = $subst{$name};
        $$self->{-override}{$name} = (reftype $init // '') eq 'CODE'
            ? $init
            : sub { $init };
        delete $$self->{-cache}{$name};
    };

    return $self;
}

=head2 clear_overrides

Remove all overrides set by C<override> call(s).

=cut

sub clear_overrides {
    my $self = shift;
    delete $$self->{-cache}{$_}
        for keys %{ $$self->{-override} };
    delete $$self->{-override};
    return $self;
};

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

=head2 clean_cache

Remove all cached resources.

No cleanup is called whatsoever, but it may be added in the future.

=cut

sub clean_cache {
    my $self = shift;
    delete $$self->{-cache};
    return $self;
};

=head2 set_cache

Set or delete a resource in the cache.

=over

=item * set_cache( resource_name => [ $instance ], ... )

Set a resource without argument.

=item * set_cache( resource_name => [ argument => $instance, ... ], ... )

Set resource with arguments. Note that the argument checks will still be applied.

=item * set_cache( resource_name => { argument => $instance, ... }, ... )

Ditto.

=item * set_cache( resource_name => undefined, ... )

Clear cache for given resource(s), regardless of arguments.

=back

Note that C<set_cache( resource_name =E<gt> $instance )> is invalid
as it may not be possible to distinguish it from one of the above forms.

=cut

sub set_cache {
    my ($self, %resources) = @_;

    RES: for my $name (keys %resources) {
        my $toset = $resources{$name};

        my $spec = $$self->{-spec}->spec($name);
        croak "Attempt to set unknown resource '$name'"
            unless $spec;

        if (!defined $toset) {
            delete $$self->{-cache}{$name};
            next RES;
        } elsif (ref $toset eq 'ARRAY') {
            unshift @$toset, '' if scalar @$toset == 1;
            $toset = { @$toset };
        } elsif (ref $toset eq 'HASH') {
            # do nothing
        } else {
            croak "set_cache value must be undef, an array, or a hash, not "
                .(ref $toset || "a scalar value '$toset'");
        };

        for (keys %$toset) {
            croak "Attempt to set illegal argument '$_' for resource '$name'"
                unless $spec->{argument}->( $_ );
            $$self->{-cache}{$name}{$_} = $toset->{$_};
        }
    };

    return $self;
}

=head2 cached( $resource_name, [$argument] )

Return a cached resource instance without initializing
(or C<undef> if the resource was never initialized).

=cut

sub cached {
    my ($self, $name, $arg) = @_;
    return $$self->{-cache}{$name}{$arg // ''};
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

    my $list = $$self->{-spec}->{preload};
    for my $name (@$list) {
        my $unused = $$self->$name;
    };
    return $self;
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
