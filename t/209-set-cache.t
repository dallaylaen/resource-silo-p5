#!/usr/bin/env perl

=head1 DESCRIPTION

Forcibly set stuff in cache.

=cut

use strict;
use warnings;
use Test::More;
use Test::Exception;

{
    package My::App;
    use Resource::Silo;
    use List::Util qw(sum);

    resource fib => argument => qr/\d+/, sub {
        my ($self, $name, $arg) = @_;
        return ($arg <= 1) ? $arg : $self->$name($arg-1) + $self->$name($arg-2);
    };

    resource prices => sub {
        my $self = shift;
        my $tmp = { foo => 42, bar => 137 };
        $self->ctl->set_cache( prices => [ $tmp ] );
        return { %$tmp, total => sum( values %$tmp ) };
    }
}

subtest 'normal op' => sub {
    my $res = My::App->new;
    is $res->fib(10), 55, 'normal instantiation';

    $res->ctl->set_cache(fib => [ 11 => 55 ]);
    is $res->fib(11), 55, 'set cache worked';
    is $res->fib(12), 110, 'derived resources work, too';

    $res->ctl->set_cache( fib => undef );
    is $res->fib(11), 89, 'cache erased => normal values';

    $res->ctl->set_cache( fib => undef )->set_cache( fib => { 1 => 2 } );
    is $res->fib(5), 10, 'doubled 1st number => all doubled';
    is $res->fib(10), 110, 'doubled 1st number => all doubled';
};

subtest 'bootstrap' => sub {
    my $res = My::App->new;
    is_deeply $res->prices,
        { foo => 42, bar => 137, total => 42 + 137 },
        'Bootstrapping a resource through an incomplete value';
};

subtest 'errors' => sub {
    my $res = My::App->new;

    throws_ok {
        $res->ctl->set_cache( dbh => undef );
    } qr/unknown.*'dbh'/, 'unknown resource = no go';

    throws_ok {
        $res->ctl->set_cache( fib => [ zzz => 333 ] );
    } qr/argument.*'zzz'.*'fib'/, 'invalid argument = no go';

    throws_ok {
        $res->ctl->set_cache( fib => bless {}, 'No::Package' );
    } qr/must be.*array.* or .* hash.* not No::Package/, 'some blessed value = no go';

    throws_ok {
        $res->ctl->set_cache( fib => 144 );
    } qr/must be.*array.* or .* hash.* not a scalar/, 'some scalar value = no go';
};

done_testing;
