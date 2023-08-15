#!/usr/bin/env perl

=head1 DESCRIPTION

Bread::Board-like class-based initializer.

=cut

use strict;
use warnings;
use Test::More;
use Test::Exception;

use lib __FILE__.".lib";

use Resource::Silo;

resource const  => sub { 42 };
resource square =>
    argument        => qr(\d+),
    init            => sub { $_[2] * $_[2] };

resource class  =>
    class           => 'My::Resource',
    dependencies    => { foo => ['const'], bar => ['square', 9] };

my $container = silo->new;

is $INC{'My/Resource.pm'}, undef, "module not loaded";

my $item = $container->class;

is $INC{'My/Resource.pm'}, __FILE__.".lib/My/Resource.pm", "module loaded now";
is ref $item, 'My::Resource', "value of expected class returned";
is $item->{foo}, 42, "constant dependency present";
is $item->{bar}, 81, "parametrized dependency present";

done_testing;

