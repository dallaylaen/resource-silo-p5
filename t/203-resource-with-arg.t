#!/usr/bin/env perl

=head1 DESCRIPTION

Test passing parameters to resources.

=cut

use strict;
use warnings;
use Test::More;
use Test::Exception;

{
    package My::Project;
    use Resource::Silo;
    resource real_foo   => sub { 0 };
    resource foo        =>
        argument            => qr/[0-9]+/,
        init                => sub { $_[0]->real_foo + $_[2] };
    resource recursive  =>
        argument            => qr/[0-9]+/,
        init                => sub {
            my ($self, $name, $arg) = @_;
            return $arg <= 1? $arg : $self->$name($arg - 1) + $self->$name($arg - 2);
        };
}

my $inst = My::Project->new( real_foo => 42 );

lives_and {
    is $inst->foo( 0 ), 42, 'resource with args works';
    is $inst->foo( '11' ), 53, 'and another one';
};

throws_ok {
    $inst->foo;
} qr/resource 'foo'/, 'missing arg';

throws_ok {
    $inst->foo( {} );
} qr/resource 'foo'/, 'non-scalar arg';

throws_ok {
    $inst->foo( 'i18n' );
} qr/resource 'foo'/, 'arg mismatches rex';

lives_and {
    is $inst->recursive(10), 55, 'recursive resource instantiated';
};

done_testing;
