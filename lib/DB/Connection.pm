package DB::Connection;
use strict;
use warnings;

use DBI;
use File::Basename;
use Moo::Role;

#-----------------------------------------------------------------------------#
# Attributes                                                                  #
#-----------------------------------------------------------------------------#
has db_name       => (is => 'ro', lazy => 1, builder => 1);

#-----------------------------------------------------------------------------#
# Builders                                                                    #
#-----------------------------------------------------------------------------#
sub _build_db_name {
    die("assert - subclass should have overidden me.");
} # end sub _build_hashkey_database_name

#-----------------------------------------------------------------------------#
# Methods                                                                     #
#-----------------------------------------------------------------------------#
sub db {
    my ($self) = @_;

    unless (-e $self->db_name) {
        my $path = $self->db_name;
        my @paths;
        while ($path = dirname($path)) {
            last if $path eq '/';
            push @paths, $path;
        }

        for my $p (reverse @paths) {
            next if -d $p;
            mkdir $p;
        }
    }

    my $db = DBI->connect("dbi:SQLite:dbname=" . $self->db_name, "", "", {RaiseError => 0, PrintError => 0, AutoCommit => 0});

    unless ($db) {
        warn("DEBUG> Connect failed: " . ($DBI::errstr || 'unknown') . "\n");
    }

    return $db;
} # end sub db


sub database {
    my ($self) = @_;

    my $dsn = $self->db->{Name};
    $dsn =~ /dbname=([^;]+);?/;
    return $1 || "unknown";
} # end sub database


sub host {
    my ($self) = @_;

    my $dsn = $self->db->{Name};
    $dsn =~ /host=([^;]+);?/;
    return $1 || "localhost";
} # end sub host


sub db_now {
    my ($self, $offset) = @_;

    my $sql = "SELECT CURRENT_TIMESTAMP";
    if (defined $offset) {
	# Works with negative offsets for historic dates
	$sql = "SELECT DATE_ADD(CURRENT_TIMESTAMP, INTERVAL $offset SECOND)";
    }

    return $self->db->selectall_arrayref($sql)->[0]->[0];
} # end sub db_now


# Return the MySQL datetime for the start of the day given by the unix
# timestamp.
sub db_start_of_day {
    my ($self, $ts) = @_;

    my (@parts) = localtime($ts);
    sprintf(
	"%04d-%02d-%02d %02d:%02d:%02d",
	($parts[5] + 1900),
	($parts[4] + 1),
	($parts[3]), 0, 0, 0
	);
} # end sub db_start_of_day


# Return the MySQL datetime for the end of the day given by the unix
# timestamp.
sub db_end_of_day {
    my ($self, $ts) = @_;

    my (@parts) = localtime($ts);
    sprintf(
	"%04d-%02d-%02d %02d:%02d:%02d",
	($parts[5] + 1900),
	($parts[4] + 1),
	($parts[3]), 23, 59, 59
	);
} # end sub db_end_of_day


=pod

=head1 NAME

DB::Connection - A Moo Role for schema_managers and models

=head1 SYNOPSIS

  # An example of using this role to connect to a database called 'trackers'
  package DB::Connection::trackers;

  use Moo;
  with 'DB::Connection';

  around _build_hashkey_database_name => sub { 'ttl60s' };

  1;

=head1 DESCRIPTION

This Moo Role is meant to be used as a bridge between the data source names
specified in C<DB::SBToolsDB> and C<DB::schema_manager> and C<DB::model>
classes.

To create a new connection class, simply create a new Moo class that implementes
the C<DB::Connection> role, which includes overriding the builder routine for
hashkey_database_name.

Every 'database' actually has two distinct databases, one for production use and
one for staging.  Each "mode" of the database has its own Data Name Source (DSN)
containing the information needed to make a DBI connection to it.

=head2 Database Naming Conventions

NYI

=head2 Environment Variables

While it is possible to create a connection object to a specific database
passing the mode parameter to new(), this is more typically done through setting
environment variables.


=head2 Attributes

=head3 db

Returns a DBI database handle initialized to the environment pointed to by the
current mode.

=head3 mode

Connection objects can be in one of two modes: production or staging.  This
controls which database environment is returned by the C<db> attribute.

This can be set manually.  If not, mode is set according to the following
sources of information:

=head3 use_dbi_cache

A boolean attribute that determines whether the DBI handle will use the
'connect_cached' option, which can be helpful in certain environments (like CGI
web applications).  The default value 0, which does not use connection caching
at all.

=head2 Methods

=head3 database

Retuns the name of the SQLite database associated with the current mode.

=head3 host

Retuns the name of the SQLite database host associated with the current mode.

=cut

1;
