#!/usr/bin/env perl

=head1 DESCRIPTION

Locked mode & overrides are useful to provide test fixtures or mocks
and avoid affecting real resources in tests.

=cut

use strict;
use warnings;
use Test::More;
use Test::Exception;

{
    package My::Project;
    use Resource::Silo;
    resource config     => sub { +{ redis => 'localhost', max_users => 42 } };
    resource redis_conn => sub { $_[0]->config->{redis} };
    resource max_users  =>
        ignore_lock         => 1,
        init                => sub { $_[0]->config->{max_users} };
    resource redis      =>
        argument            => sub { 1 }, # anything goes
        ignore_lock         => 1,
        init                => sub { return ($_[0]->redis_conn . ":$_[2]") };
}

my $inst = My::Project->new;

$inst->ctl->lock->override(
    redis_conn => 'mock',
);

lives_and {
    is $inst->redis('foo'), 'mock:foo', 'redis falls through and redis_conn is mocked';
};

throws_ok {
    $inst->max_users;
} qr(initialize.*locked mode), 'loading config is prohibited';
like $@, qr('config'), 'we tried to load config, max_users was ok';

$inst->ctl->unlock;
lives_and {
    is $inst->max_users, 42, 'can instantiate after unlock';
};

done_testing;
