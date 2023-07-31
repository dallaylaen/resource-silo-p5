#!/usr/bin/env perl

=head1 DESCRIPTION

Basically emulate bootstrapping DBI via DBIx::Class
by use of set_cache (+some edge cases).

=cut

use strict;
use warnings;
use Test::More;
use Test::Exception;

my %connect;
my $seq;

{
    package My::Database;
    sub new {
        my $class = shift;
        my $id = ++$seq;
        $connect{$id}++;
        return bless {
            id => $id,
            tables => {},
        }, $class;
    };
    sub id { $_[0]->{id} };
    sub tables { $_[0]->{tables} };
};

{
    package My::Orm;
    sub new {
        my ($class, $conn) = @_;
        return bless {
            conn => $conn,
        }, $class;
    };
    sub deploy {
        my $self = shift;
        my $db = $self->{conn}->tables;
        $db->{$_}++
            for qw(foo bar quux);
    };
};

{
    package My::App;
    use Resource::Silo -class;

    resource dbh =>
        init        => sub {
            my $self = shift;
            my $dbh = My::Database->new;
            $self->ctl->set_cache( dbh => $dbh );
            $self->schema->deploy;
            return $dbh;
        },
        cleanup     => sub {
            my $dbh = shift;
            delete $connect{ $dbh->id };
        };

    resource schema =>
        init            => sub {
            my $self = shift;
            return My::Orm->new( $self->dbh );
        };
};

subtest 'basic initialisation' => sub {
    my $res = My::App->new;
    is_deeply \%connect, {}, "nothing instantiated yet";
    is_deeply $res->dbh->tables, { foo => 1, bar => 1, quux => 1 }
        , "schema seeded";
    is_deeply \%connect, { 1 => 1 }, "connection is there";
    undef $res;
    is_deeply \%connect, {}, "connection closed";
};

# TODO the instantiation must work in any order!
0 and lives_ok {
    my $res = My::App->new;
    $res->schema;
};

done_testing;
