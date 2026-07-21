#!/usr/bin/env perl

=head1 DESCRIPTION

Test on_preflight callback behavior:
- callback is invoked during preflight
- callback receives correct arguments
- callback exception propagates
- on_preflight implies preflight => 1
- works alongside parametric resources (preflight => [...])

=cut

use strict;
use warnings;
use Test::More;
use Test::Exception;

# ----------------------------------------------------------------
# Package definitions must be at file scope so closures work.
# ----------------------------------------------------------------

{
    package T::Implies;
    use Resource::Silo -class;

    our @calls;
    resource simple =>
        init         => sub { "simple_value" },
        on_preflight => sub {
            my ($inst, $container, $name, $arg) = @_;
            push @T::Implies::calls, { inst => $inst, name => $name, arg => $arg };
        };
}

{
    package T::Args;
    use Resource::Silo -class;

    our @got;
    resource check =>
        init         => sub { "check_inst" },
        on_preflight => sub {
            my ($inst, $container, $name, $arg) = @_;
            push @T::Args::got, {
                inst      => $inst,
                container => $container,
                name      => $name,
                arg       => $arg,
            };
        };
}

{
    package T::Param;
    use Resource::Silo -class;

    our @got;
    resource item =>
        argument     => qr/.*/,
        preflight    => [ 'x', 'y' ],
        init         => sub { "item_$_[2]" },
        on_preflight => sub {
            my ($inst, $container, $name, $arg) = @_;
            push @T::Param::got, { inst => $inst, name => $name, arg => $arg };
        };
}

{
    package T::Fail;
    use Resource::Silo -class;

    resource broken =>
        init         => sub { "ok" },
        on_preflight => sub {
            die "deliberate preflight failure\n";
        };
}

{
    package T::Plain;
    use Resource::Silo -class;

    our $inited = 0;
    resource plain =>
        preflight => 1,
        init      => sub { $T::Plain::inited++ };
}

{
    package T::NoPreflight;
    use Resource::Silo -class;

    our @calls;
    resource guarded =>
        init         => sub { "guarded" },
        on_preflight => sub { push @T::NoPreflight::calls, 1 };
}

# ----------------------------------------------------------------
# Tests
# ----------------------------------------------------------------

subtest 'on_preflight implies preflight => 1' => sub {
    @T::Implies::calls = ();
    lives_ok {
        T::Implies->new->ctl->preflight;
    } 'preflight runs without error';

    is scalar @T::Implies::calls, 1,
        'on_preflight callback called once for no-argument resource';
    is $T::Implies::calls[0]{name}, 'simple', 'resource name recorded correctly';
};

subtest 'callback receives correct arguments' => sub {
    @T::Args::got = ();
    my $c = T::Args->new;
    $c->ctl->preflight;

    my $got = \@T::Args::got;
    is scalar @$got, 1, 'callback called exactly once';
    is $got->[0]{inst},  'check_inst', 'first arg is the resource instance';
    isa_ok $got->[0]{container}, 'T::Args', 'second arg is the container';
    is $got->[0]{name},  'check',      'third arg is the resource name';
    is $got->[0]{arg},   undef,        'fourth arg is undef for no-argument resource';
};

subtest 'callback receives arg for parametric resource' => sub {
    @T::Param::got = ();
    T::Param->new->ctl->preflight;

    my $got = \@T::Param::got;
    is scalar @$got, 2, 'callback called once per preflight argument';
    is $got->[0]{arg},  'x',      'first call gets first arg';
    is $got->[0]{inst}, 'item_x', 'instance matches first arg';
    is $got->[1]{arg},  'y',      'second call gets second arg';
    is $got->[1]{inst}, 'item_y', 'instance matches second arg';
};

subtest 'exception in callback propagates' => sub {
    throws_ok {
        T::Fail->new->ctl->preflight;
    } qr(deliberate preflight failure), 'exception from on_preflight propagates';
};

subtest 'resources without on_preflight are unaffected' => sub {
    $T::Plain::inited = 0;
    lives_ok {
        T::Plain->new->ctl->preflight;
    } 'preflight without on_preflight still works';

    is $T::Plain::inited, 1, 'resource was still initialized during preflight';
};

subtest 'on_preflight not called when preflight() is not invoked' => sub {
    @T::NoPreflight::calls = ();
    my $c = T::NoPreflight->new;
    is $c->guarded, 'guarded', 'resource accessible normally';
    is scalar @T::NoPreflight::calls, 0,
        'on_preflight not called when ctl->preflight() is not invoked';
};

done_testing;
