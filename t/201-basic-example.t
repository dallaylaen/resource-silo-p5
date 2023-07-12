#!/usr/bin/perl

=head1 DESCRIPTION

Use Resource::Silo DLS with conf & DBI, make sure happy path works.

=cut

use strict;
use warnings;
use Test::More;

BEGIN {
    package My::Project::Res;
    use Resource::Silo;
    use YAML::XS qw(LoadFile);
    use DBI;
    use DBD::SQLite;

    resource config      => sub { LoadFile( $_[0]->config_path ) };
    resource config_path => sub { __FILE__.".yaml" };
    resource dbh         => sub {
        my $self = shift;
        my $conf = $self->config->{dbh};
        DBI->connect( "dbi:$conf->{driver}:database=$conf->{database}", '', '', { RaiseError => 1 } );
    };

    $INC{ (__PACKAGE__ =~ s#::#/#gr).".pm" } = __FILE__;
    1;
};

use My::Project::Res;

is silo->cached("config"), undef, 'config not loaded yet';

my $dbh = silo->dbh;

ok ref $dbh, 'SLQite loaded';
is ref silo->cached('config'), 'HASH', 'config loaded';
is silo->cached('config')->{foo}, 42, 'known value present in config';

done_testing;
