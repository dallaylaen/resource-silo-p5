#!/usr/bin/env perl

=head1 DESCRIPTION

Tests for the resource_ctl() function:
  - resource_ctl() with no arguments returns the correct metadata object;
  - resource_ctl( some_unknown_field => 1 ) dies with a descriptive error;
  - resource_ctl( trace => 1 ) dies because trace must be a function.

=cut

use strict;
use warnings;
use Test::More;
use Test::Exception;

use Resource::Silo;

resource foo => sub { 42 };

my $meta = silo->ctl->meta;
is ref $meta, 'Resource::Silo::Metadata', 'silo->ctl->meta is a Metadata object';

subtest 'resource_ctl() returns the metadata object' => sub {
    my $ret = resource_ctl();
    is $ret, $meta, 'resource_ctl() returns the same metadata object as silo->ctl->meta';
};

subtest 'resource_ctl errors' => sub {
    throws_ok {
        resource_ctl( some_unknown_field => 1 );
    } qr/Unknown option 'some_unknown_field'/, 'unknown field dies with descriptive error';

    throws_ok {
        resource_ctl( trace => 1 );
    } qr/'on_trace' must be a function/, 'trace => non-coderef dies with descriptive error';
};

done_testing;
