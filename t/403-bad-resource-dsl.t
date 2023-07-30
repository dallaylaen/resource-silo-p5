#!/usr/bin/env perl

=head1 DESCRIPTION

Various errors in DSL.

=cut

use strict;
use warnings;

do {
    package My::App;
    use Test::More;
    use Test::Exception;
    use Resource::Silo;

    throws_ok {
        resource;
    } qr(^resource: .*identifier), 'no undef names';

    throws_ok {
        resource [], sub { };
    } qr(^resource: .*identifier), 'no refs in names';

    throws_ok {
        resource 42, sub { };
    } qr(^resource: .*identifier), 'names must be identifiers';

    throws_ok {
        resource '$', sub { };
    } qr(^resource: .*identifier), 'names must be identifiers';

    throws_ok {
        resource 'identifier_foolowed_by_$', sub { };
    } qr(^resource: .*identifier), 'names must be identifiers';

    throws_ok {
        resource new => sub { };
    } qr(^resource: .*replace.*method), 'known method = no go';
    my $where = __FILE__." line ".(__LINE__-2);
    like $@, qr($where), 'error attributed correctly';

    throws_ok {
        resource ctl => sub { };
    } qr(^resource: .*replace.*method), 'known method = no go';

    throws_ok {
        resource foo => sub { };
        resource foo => sub { };
    } qr(^resource: .*redefine.*resource), 'no duplicates';

    throws_ok {
        resource bar => supercharge => 42, init => sub { };
    } qr(^resource: .*unknown), 'unknown parameters = no go';

    throws_ok {
        resource 'naked';
    } qr(^resource: .*init), 'init missing = no go';

    throws_ok {
        resource with_param => argument => 42, sub { };
    } qr(^resource: .*argument.*regex), 'wrong argument spec';

    throws_ok {
        resource bad_order => cleanup_delay => 'never', sub { };
    } qr(^resource: .*cleanup_delay.*number), 'wrong cleanup order spec';

    throws_ok {
        resource bad_cleanup => cleanup => {}, sub { };
    } qr(^resource: .*\bcleanup\b.*function), 'wrong cleanup method spec';

    throws_ok {
        resource cleanup_wo_cache =>
            cleanup                 => sub {},
            ignore_cache            => 1,
            init                    => sub {};
    } qr(^resource:.* cleanup .* ignore_cache), 'cleanup incompatible with nocache';

    done_testing;
}

