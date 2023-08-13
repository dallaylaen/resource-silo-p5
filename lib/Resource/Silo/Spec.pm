package Resource::Silo::Spec;

use strict;
use warnings;
our $VERSION = '0.02';

=head1 NAME

Resource::Silo::Spec - description of known resource types for L<Resource::Silo>

=head1 METHODS

=cut

use Carp;
use Scalar::Util qw( looks_like_number reftype );

my $ID_REX = qr/^[a-z][a-z_0-9]*$/i;

# Define possible reftypes portably
my $CODE   = reftype sub { };
my $REGEXP = ref qr/.../;
sub _is_empty { $_[0] eq '' };

=head2 new( $target )

$target is the name of the module where resource access methods will be created.

=cut

sub new {
    my ($class, $target) = @_;
    return bless {
        -target  => $target,
        -preload => [],
    }, $class;
};

=head2 add( $resource_name, ... )

Create resource type. See L<Resource::Silo/resource> for details.

=cut

my %known_args = (
    argument        => 1,
    dependencies    => 1,
    derivative      => 1,
    cleanup         => 1,
    cleanup_order   => 1,
    fork_cleanup    => 1,
    ignore_cache    => 1,
    init            => 1,
    preload         => 1,
);
sub add {
    my $self = shift;
    my $name = shift;
    if (@_ % 2) {
        my $init = pop @_;
        unshift @_, init => $init;
    }
    my (%spec) = @_;
    my $target = $self->{-target};

    croak "resource: name must be an identifier"
        unless defined $name and !ref $name and $name =~ $ID_REX;
    croak "resource: attempt to redefine resource '$name'"
        if $self->spec($name);
    croak "resource: attempt to replace existing method '$name' in $target"
        if $target->can($name);

    my @extra = grep { !$known_args{$_} } keys %spec;
    croak "resource '$name': unknown arguments in specification: @extra"
        if @extra;

    if (my $deps = delete $spec{dependencies}) {
        croak "resource '$name': 'dependencies' must be an array"
            unless ref $deps eq 'ARRAY';
        my @bad = grep { !/$ID_REX/ } @$deps;
        croak "resource '$name': illegal dependency name(s): "
            .join ", ", map { "'$_'" } @bad
                if @bad;
        $spec{allowdeps} = { map { $_ => 1 } @$deps };
    };

    croak "resource '$name': 'init' must be a function"
        unless ref $spec{init} and reftype $spec{init} eq $CODE;

    if (!defined $spec{argument}) {
        $spec{argument} = \&_is_empty;
    } elsif (ref $spec{argument} eq $REGEXP) {
        my $rex = qr(^(?:$spec{argument})$);
        $spec{argument} = sub { $_[0] =~ $rex };
    } elsif ((reftype $spec{argument} // '') eq $CODE) {
        # do nothing, we're fine
    } else {
        croak "resource '$name': 'argument' must be a regexp or function";
    }

    $spec{cleanup_order} //= 0;
    croak "resource '$name': 'cleanup_order' must be a number"
        unless looks_like_number($spec{cleanup_order});

    croak "resource '$name': 'cleanup*' is useless while 'ignore_cache' is in use"
        if $spec{ignore_cache} and (
            defined $spec{cleanup}
            or defined $spec{fork_cleanup}
            or $spec{cleanup_order} != 0
        );

    croak "resource '$name': 'cleanup' must be a function"
        if defined $spec{cleanup} and (reftype $spec{cleanup} // '') ne $CODE;
    croak "resource '$name': 'fork_cleanup' must be a function"
        if defined $spec{fork_cleanup} and (reftype $spec{fork_cleanup} // '') ne $CODE;

    if ($spec{preload}) {
        push @{ $self->{-preload} }, $name;
    };

    $self->{$name} = \%spec;

    # Move code generation into Resource::Silo::Container
    # so that exceptions via croak() are attributed correctly.
    {
        no strict 'refs'; ## no critic Strictures
        *{"${target}::$name"} =
            Resource::Silo::Container::_make_resource_accessor($name, \%spec);
    }

    return $self;
};

=head2 spec

Fetch specifications for given resource.

=cut

# TODO name!!!
sub spec {
    my ($self, $name) = @_;
    croak "Illegal resource name '$name'"
        unless $name =~ $ID_REX;
    return $self->{$name};
};

=head2 generate_dsl

Create C<resource> function closed over current object.

=cut

# TODO name!!
sub generate_dsl {
    my $inst = shift;
    return sub { $inst->add(@_) };
};

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2023, Konstantin Uvarin, C<< <khedin@gmail.com> >>

This program is free software.
You can redistribute it and/or modify it under the terms of either:
the GNU General Public License as published by the Free Software Foundation,
or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.

=cut

1;
