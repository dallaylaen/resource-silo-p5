# DESCRIPTION

Resource::Silo is a lazy declarative resource managemement library for Perl.

What it offers:

## Exported functions:

* `resource` - a Moose-like prototyped function to declare resources
inside a sealed container class;
* `silo` - a re-exportable function to access
the one and true container instance;
* no limitations on creating more than one container objects or even classes.

## Inside the application:

* acquiring resources on demand as simple as `silo->my_foo`;
* caching them;
* releasing them in due order when program ends;
* preloading all resources at startup to fail early;
* detecting forks and reinitializing to avoid clashes.

## In test files:

* overriding actual resources with mocks;
* locking the container so that no unmocked resources can be acquired.

## In support scripts and tools:

* loading only the needed resources for fast startup time;
* creating isolated one-off resource instances to perform invasive operations
such as a big DB update within a transaction.

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

Declaring a parametric resource:

```perl
    package My::App;
    use Resource::Silo;

    use Redis;
    use Redis::Namespace;
    resource redis_conn => sub {
        my $self = shift;
        Redis->new( server => $self->config->{redis} );
    };
    resource redis =>
        argument      => sub { $known_namespaces{ $_ } },
        init          => sub {
            my ($self, $name, $ns) = @_;
            Redis::Namespace->new(
                redis     => $self->redis,
                namespace => $ns,
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

Performing a Big Scary Update:

```perl
    use My::App qw(silo);
    my $dbh = silo->ctl->fresh('dbh');

    $dbh->begin_work;
    # any operations on $dbh won't interfere with normal DB usage
    # of silo->dbh by other application classes.
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

