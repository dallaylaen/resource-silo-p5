package Resource::Silo::Spec;

use strict;
use warnings;

=head1 NAME

Resource::Silo::Spec - description of known resource types for L<Resource::Silo>

=head1 METHODS

=cut

use Carp;
use Scalar::Util qw( looks_like_number reftype );

my $ID_REX = qr/^[a-z][a-z_0-9]*$/i;

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
    assume_pure     => 1,
    cleanup         => 1,
    cleanup_order   => 1,
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
    croak "resource: attempt to replace existing method in $target"
        if $target->can($name);

    my @extra = grep { !$known_args{$_} } keys %spec;
    croak "resource: unknown arguments in specification: @extra"
        if @extra;

    croak "resource: init must be a function"
        unless $spec{init} and reftype $spec{init} eq 'CODE';

    if (!defined $spec{argument}) {
        $spec{argument} = sub { $_[0] eq ''};
    } elsif ((reftype $spec{argument} // '') eq 'REGEXP') {
        my $rex = qr(^(?:$spec{argument})$);
        $spec{argument} = sub { $_[0] =~ $rex };
    } elsif ((reftype $spec{argument} // '') eq 'CODE') {
        # do nothing, we're fine
    } else {
        croak "resource: argument must be a regexp or function";
    }

    $spec{cleanup_order} //= 0;
    croak "resource: cleanup_order must be a number"
        unless looks_like_number($spec{cleanup_order});

    if (defined $spec{cleanup}) {
        croak "resource: cleanup must be a function"
            unless reftype $spec{cleanup} eq 'CODE';
        croak "resource: cleanup is useless while ignore_cache is in use"
            if $spec{ignore_cache};
    }

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

1;
