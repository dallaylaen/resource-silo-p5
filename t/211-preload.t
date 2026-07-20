#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

use Resource::Silo;

# TODO verify that a 'require'd module preflight is attempted!

my %started = ();
resource foo =>
    preflight     => 1,
    init        => sub { $started{$_[1]}++ };
resource bar =>
    init        => sub { $started{$_[1]}++ };
resource quux =>
    init        => sub { 42 };
resource with_args =>
    preflight     => [ 'first', 'last' ],
    argument    => qr/.*/,
    init        => sub { $started{"$_[1]:$_[2]"}++ };

subtest 'before preflight' => sub {
    is silo->quux, 42, 'unconditional resource';
    is_deeply \%started, {}, 'no preflight called = empty';
};

subtest 'after preflight' => sub {
    silo->ctl->preflight;
    is_deeply \%started,
        { foo => 1, "with_args:first" => 1, "with_args:last" => 1 },
        'preflight called = preloaded';
};

done_testing;
