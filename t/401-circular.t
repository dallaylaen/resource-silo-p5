#!/usr/bin/env perl

=head1 DESCRIPTION

Ensure circular dependencies don't go wild

=cut

use strict;
use warnings;
use Test::More;
use Test::Exception;

{
    package My::Project;
    use Resource::Silo;

    resource foo => sub { $_[0]->bar };
    resource bar => sub { $_[0]->foo };
}

my $file = __FILE__;
my $line;

throws_ok {
    # force fatal warnings
    local $SIG{__WARN__} = sub { die $_[0] };
    my $inst = My::Project->new;
    $line = __LINE__; $inst->foo;
} qr/[Cc]ircular dependency/, 'circulalrity detected';

like $@, qr($file line $line), 'error attributed correctly';

note $@;

done_testing;
