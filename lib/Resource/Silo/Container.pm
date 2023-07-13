package Resource::Silo::Container;

use strict;
use warnings;

=head1 NAME

Resource::Silo::Container - base resource storage class for L<Resource::Silo>.

=head1 DESCRIPTION

=head1 METHODS

=cut

use Carp;
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

=head2 fetch( $resource_name )

Fetch resource, lazily initializing it.

Typically C<silo-E<gt>foo> will call C<silo-E<gt>fetch("foo")> internally.

=cut

sub fetch {
    my ($self, $name, $arg) = @_;
    # TODO arg unused

    croak "Arguments for resources unimplemented"
        if defined $arg;

    if ($self->{pid} != $$) {
        delete $self->{rw_cache};
        $self->{pid} = $$;
    };

    my $key = $name . (defined $arg ? "\@$arg" : '');

    return $self->{rw_cache}{$key} //= do {
        if ($self->{pending}{$key}) {
            my $loop = join ', ', sort keys %{ $self->{pending} };
            croak "Circular dependency detected for resource $key: {$loop}";
        };
        local $self->{pending}{$key} = 1;

        $self->{spec}->init($name)->($self, $name, $arg);
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
