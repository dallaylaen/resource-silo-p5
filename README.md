# DESCRIPTION

Resource::Silo is a lazy declarative resource managemement library for Perl.

It allows to declare resources such as configuration files, loggers,
database connections, external service endpoints, and the like.
It will subsequently create a container object that handles
acquiring said resources on demand, caching, and releasing in due order,
as well as replacing them with test fixtures
and creating one-off resource instances for specific tasks.

# USAGE

Declaring a resource:

```perl
    package My::App;
    use Resource::Silo;
    use DBI;
    use YAML::XS qw(LoadFile);

    resource config => sub { LoadFile( "/etc/myapp.yaml" ) };
    resource dbh    => sub {
      my $self = shift;
      my $conf = $self->config->{database};
      DBI->connect(
        $conf->{dbi}, $conf->{username}, $conf->{password}, { RaiseError => 1 }
      );
    };
```

Using it elsewhere:

```perl
    use My::App qw(silo);

    sub load_foo {
      my $id = shift;
      my $sql = q{SELECT * FROM foo WHERE foo_id = ?};
      silo->dbh->fetchrow_hashred( $sql, $id );
    };
```

```perl
    package My::App::Stuff;
    use Moo;
    use My::App qw(silo);
    has dbh => is => 'lazy', builder => sub { silo->dbh };
```

Using it in test files:

```perl
    use Test::More;
    use My::App qw(silo);

    silo->ctl->override( dbh => $temp_sqlite_connection );
    silo->ctl->lock;

    my $stuff = My::App::Stuff->new();
    $stuff->frobnicate( ... );          # will only affect the sqlite instance
    my $conf = silo->config;            # oops! this dies because no override
                                        # was supplied and lock is in action!
```

# INSTALLATION

To install this module, run the following commands:

	perl Makefile.PL
	make
	make test
	make install

# LICENSE AND COPYRIGHT

This software is free software.

Copyright (c) 2023 Konstantin Uvarin (khedin@gmail.com).

