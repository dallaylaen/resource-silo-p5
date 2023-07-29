#!/usr/bin/env perl

=head1 DESCRIPTION

Make sure that custom destrurction is executed correctly.

=cut

use strict;
use warnings;
use Test::More;

my $conn_id;
my %active;
{
    package My::App;
    use Resource::Silo -class;
    resource foo =>
        init        => sub {
            my $n = ++$conn_id;
            $active{$n}++;
            return $n;
        },
        cleanup     => sub {
            my $item = shift;
            delete $active{ $item };
        };
}

subtest 'alone' => sub {
    my $res = My::App->new;

    is $res->foo, 1, 'new instance created';
    is_deeply \%active, { 1 => 1 }, "active connection exists";

    undef $res;
    is_deeply \%active, {}, "cleanup worked";
};

done_testing;
