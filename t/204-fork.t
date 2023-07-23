#!/usr/bin/env perl

=head1 DESCRIPTION

Ensure that forking erases cache.

=cut

use strict;
use warnings;

{
    package My::Res;
    use Resource::Silo -class;
    my $count;
    resource foo => sub { ++$count };
}

my $inst = My::Res->new;

my $fst = $inst->foo;
my $snd = $inst->foo;

if (my $pid = fork // die "Fork failed: $!") {
    waitpid $pid, 0;
    exit $? >> 8;
} else {
    # make sure Test::More return nonzero status on error
    # so call it after fork
    require Test::More;
    Test::More->import();

    is( $fst, 1, "first call to foo correct" );
    is( $snd, 1, "second call to foo cached" );
    is( $inst->foo, 2, "call within a fork causes reinit" );

    done_testing();
}
