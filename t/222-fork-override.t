#!/usr/bin/env perl

=head1 DESCRIPTION

Test that an override immediately after a fork calls the right cleanup type

=cut

use strict;
use warnings;
use Test::More;

BEGIN {
    eval { require JSON::PP; 1 }
        or do { plan skip_all => "JSON not found"; exit };
    JSON::PP->import();
};

sub run_fork(&); ## no critic 'prototypes'

my %trace;
{
    package My::App;
    use Resource::Silo -class;

    my $id;
    resource normal =>
        init => sub {
            my $label = $_[1]. "_" . ++$id;
            $trace{"init_$label"}++;
            return $label;
        },
        cleanup => sub {
            my $label = shift;
            $trace{"cleanup_$label"}++;
        };

    resource aware =>
        init => sub {
            my $label = $_[1]. "_" . ++$id;
            $trace{"init_$label"}++;
            return $label;
        },
        cleanup => sub {
            my $label = shift;
            $trace{"cleanup_$label"}++;
        },
        fork_cleanup => sub {
            my $label = shift;
            $trace{"forked_$label"}++;
        };

    resource safe =>
        fork_safe => 1,
        init => sub {
            my $label = $_[1]. "_" . ++$id;
            $trace{"init_$label"}++;
            return $label;
        },
        cleanup => sub {
            my $label = shift;
            $trace{"cleanup_$label"}++;
        };
};

my $inst = My::App->new;
my $unused = [$inst->normal, $inst->aware, $inst->safe];

subtest 'override normal resource after fork' => sub {
    my $data = run_fork {
        $inst->ctl->override( normal => 'foo' );
        return \%trace;
    };

    is_deeply $data, {
        %trace,
        cleanup_normal_1 => 1,
        forked_aware_2 => 1,
    }, "trace as expected";
};

subtest 'override fork-aware resource after fork' => sub {
    my $data = run_fork {
        $inst->ctl->override( aware => 'foo' );
        return \%trace;
    };

    is_deeply $data, {
        %trace,
        cleanup_normal_1 => 1,
        forked_aware_2 => 1,
    }, "trace as expected";
};

subtest 'override fork-safe resource after fork' => sub {
    my $data = run_fork {
        $inst->ctl->override( safe => 'foo' );
        return \%trace;
    };

    is_deeply $data, {
        %trace,
        cleanup_normal_1 => 1,
        forked_aware_2 => 1,
        cleanup_safe_3 => 1,
    }, "trace as expected";
};

subtest 'obtain fork-safe value' => sub {
    my $data = run_fork {
        my $new = $inst->safe;
        return { %trace, new_value => $new };
    };

    is_deeply $data, {
        %trace,
        cleanup_normal_1 => 1,
        forked_aware_2 => 1,
        new_value => 'safe_3',
    }, "trace as expected";
};

done_testing;

sub run_fork(&) { ## no critic 'prototypes'
    my $code = shift;

    pipe my $r, my $w
        or die "pipe failed: $!";
    my $pid = fork;
    die "Fork failed: $!" unless defined $pid;

    if ($pid) {
        close $w;
        local $/;
        my $result = <$r>;
        waitpid( $pid, 0 );
        return decode_json($result);
    } else {
        close $r;
        my $result = $code->();
        print $w encode_json($result);
        close $w;
        exit;
    };
};

