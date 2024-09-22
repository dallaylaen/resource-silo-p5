#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

{
    package My::App224;
    use Resource::Silo -class;

    resource foo =>
        init        => sub { 41 },
        post_init   => sub {
            my ($self, $container) = @_;
            die "foo must be a number"
                    unless $self =~ /^\d+$/;
            return $self + 1;
        };
}

subtest 'normal usage' => sub {
    my $app = My::App224->new;
    lives_and {
        is $app->foo, 42, "default value incremented";
    }
};

subtest 'good override' => sub {
    my $app = My::App224->new(foo => 21);
    lives_and {
        is $app->foo, 22, "overridden value implemented";
    }
};

subtest 'bad override' => sub {
    my $app = My::App224->new(foo => "foo bared");

    # delayed check is bad but we cannot guarantee it anyway.
    # use 'preload' to check all the resources
    throws_ok {
        $app->foo;
    } qr/.*number/;
};

done_testing;
