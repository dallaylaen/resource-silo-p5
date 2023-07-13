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

    done_testing;
}

