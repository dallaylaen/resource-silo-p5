#!/usr/bin/env perl

=head1 DESCRIPTION

seal() runs consistency checks without initializing anything,
and prevents any further resource declarations.

=cut

use strict;
use warnings;
use Test::More;
use Test::Exception;

# --- happy path: seal on a consistent setup ---
{
    package My::Silo::Good;
    use Resource::Silo;
    resource config => sub { +{ x => 1 } };
    resource derived =>
        derived      => 1,
        dependencies => [qw( config )],
        init         => sub { $_[0]->config->{x} };

    ::lives_ok { resource_ctl->seal } 'seal succeeds on consistent metadata';

    # Resources still work after sealing
    ::is silo->derived, 1, 'resources accessible after seal';

    # Cannot add more resources after sealing
    ::throws_ok {
        resource( extra => sub { 42 } );
    } qr/sealed/, 'cannot add resource to sealed metadata';
}

# --- error path: seal on setup with unsatisfied forward deps ---
{
    package My::Silo::Bad;
    use Resource::Silo;
    resource broken =>
        dependencies => [qw( missing )],
        init         => sub { 1 };
    # 'missing' is never declared

    ::throws_ok {
        resource_ctl->seal;
    } qr/Unsatisfied/, 'seal dies when forward deps are unresolved';
}

# --- seal does not initialize resources ---
{
    package My::Silo::Lazy;
    use Resource::Silo;
    our $inited = 0;
    resource expensive => sub { $inited++; 'value' };

    resource_ctl->seal;
}
is $My::Silo::Lazy::inited, 0, 'seal does not initialize any resources';

done_testing;
