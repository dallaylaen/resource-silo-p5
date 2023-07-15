#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

my $counter = 0;
{
    package My::App;
    use Resource::Silo;
    resource bunny =>
        ignore_cache    => 1,
        init            => sub { ++$counter };
};

my $inst = My::App->new;

is $inst->bunny, 1, 'first bunny';
is $inst->bunny, 2, 'second bunny';
is $inst->bunny, 3, 'third bunny';

done_testing;
