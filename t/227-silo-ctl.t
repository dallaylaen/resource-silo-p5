#!/usr/bin/env perl

=head1 DESCRIPTION

Tests for the silo_ctl() function:
  - silo_ctl() with no arguments returns the correct metadata object;
  - silo_ctl( trace => sub { ... } ) sets $meta->trace;
  - silo_ctl( some_unknown_field => 1 ) dies with a descriptive error;
  - silo_ctl( trace => 1 ) dies because trace must be a function.

=cut

use strict;
use warnings;
use Test::More;
use Test::Exception;

use Resource::Silo;

resource foo => sub { 42 };

my $meta = silo->ctl->meta;
is ref $meta, 'Resource::Silo::Metadata', 'silo->ctl->meta is a Metadata object';

subtest 'silo_ctl() returns the metadata object' => sub {
    my $ret = silo_ctl();
    is $ret, $meta, 'silo_ctl() returns the same metadata object as silo->ctl->meta';
};

subtest 'silo_ctl trace => sub { ... } sets $meta->trace' => sub {
    my $tracer = sub { "traced: $_[0]" };
    silo_ctl( trace => $tracer );
    is $meta->trace, $tracer, 'trace is set on the metadata object';
};

subtest 'silo_ctl errors' => sub {
    throws_ok {
        silo_ctl( some_unknown_field => 1 );
    } qr/Unknown option 'some_unknown_field'/, 'unknown field dies with descriptive error';

    throws_ok {
        silo_ctl( trace => 1 );
    } qr/'trace' must be a function/, 'trace => non-coderef dies with descriptive error';
};

done_testing;
