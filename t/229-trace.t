#!/usr/bin/env perl

=head1 DESCRIPTION

Tests for the on_trace callback:
  - silo_ctl( trace => sub { ... } ) sets the trace callback;
  - the callback receives ($container, $message) on resource init;
  - the callback receives ($container, $message) on resource cleanup.

=cut

use strict;
use warnings;
use Test::More;

use Resource::Silo;

resource foo => sub { 42 };

my @log;
silo_ctl( trace => sub {
    my ($container, $msg) = @_;
    push @log, { container => $container, msg => $msg };
});

subtest 'trace callback is set' => sub {
    isnt silo->ctl->meta->on_trace, undef, 'on_trace is set';
};

subtest 'trace callback fires on init with ($container, $message)' => sub {
    @log = ();
    my $val = silo->foo;
    is $val, 42, 'resource returns correct value';
    is scalar @log, 1, 'one trace event fired';
    is ref $log[0]{container}, ref silo, 'container is passed correctly';
    like $log[0]{msg}, qr/foo/, 'message mentions resource name';
};

subtest 'trace callback fires on cleanup with ($container, $message)' => sub {
    @log = ();
    silo->ctl->cleanup;
    is scalar @log, 1, 'one trace event fired on cleanup';
    is ref $log[0]{container}, ref silo, 'container is passed correctly';
    like $log[0]{msg}, qr/foo/, 'message mentions resource name';
};

done_testing;
