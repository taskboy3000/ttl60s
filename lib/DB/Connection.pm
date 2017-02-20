package DB::Connection;
use strict;
use warnings;

use DBI;
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

    if (defined $self->{__db} && $self->{__db}->ping) {
	return $self->{__db};
    } else {
	delete $self->{__db};
    }

    $self->{__db} = DBI->connect("dbi:SQLite:dbname=" . $self->db_name, "", "", {RaiseError => 0, PrintError => 0, AutoCommit => 0});
} # end sub db


sub database {
    my ($self) = @_;

    my $dsn = $self->db->{Name};
    $dsn =~ /database=([^;]+);?/;
    return $1 || "unknown";
} # end sub database


sub host {
    my ($self) = @_;

    my $dsn = $self->db->{Name};
    $dsn =~ /host=([^;]+);?/;
    return $1 || "unknown";
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

sb_db::connection - A Moo Role for schema_managers and models

=head1 SYNOPSIS

  # An example of using this role to connect to a database called 'trackers'
  package sb_db::connection::trackers;
  use CPAN::sb_cpan_lib;
  use Moo;
  with 'sb_db::connection';

  around _build_hashkey_database_name => sub { 'Trackers' };

  around _build_use_dbi_cache => sub {1};

  1;

=head1 DESCRIPTION

This Moo Role is meant to be used as a bridge between the data source names
specified in C<sb_db::SBToolsDB> and C<sb_db::schema_manager> and C<sb_db::model>
classes.

To create a new connection class, simply create a new Moo class that implementes
the C<sb_db::connection> role, which includes overriding the builder routine for
hashkey_database_name.

Every 'database' actually has two distinct databases, one for production use and
one for staging.  Each "mode" of the database has its own Data Name Source (DSN)
containing the information needed to make a DBI connection to it.

=head2 Database Naming Conventions

Each supported database is in a hash within SBToolsDB.pm.  The hash key for each
DSN is composed of three concatentated parts: region, database name, and mode.
The region is a two or three letter abbreviation that matches the MathWorks
standard environment variable LOCATION.  The database name is an arbitrary
label, but should be some form of the database name.  The mode may be either
'Test', for staging or an empty string for production.  For example,
'TYOTrackersTest' is the hashkey for the DSN of the trackers_test staging
database for the Toyko office.  'SETrackers' is the DSN of the trackers
production database in Sweden.

=head2 Environment Variables

While it is possible to create a connection object to a specific database
passing the mode parameter to new(), this is more typically done through setting
environment variables.

=over 4

=item SBTOOLS_DATABASE_LOCATION

This environment is also used by SBToolsDB.pm.  It is expected to match one of
the keys of the %gDatabases hash within SBToolsDB.pm.

However, connection objects are tied to a specific production-staging pair of
DSN.  Because of this, this role merely looks at the value of the environment
variable to see if it ends in 'Test'.  If so, the connection object's mode is
set to 'staging' and the DSN for the staging database for the managed schema is
used.  Otherwise, the mode is set to 'production'.

=item SBTOOLS_DATABASE_MODE

To move away from the above legacy code, the new environment
SBTOOLS_DATABASE_MODE takes precedence over SBTOOLS_DATABASE_LOCATION.  It is
expected to be either 'staging' or 'production'.  The case of the string does
not matter.

    =cut
    
=head2 Attributes

=head3 db

Returns a DBI database handle initialized to the environment pointed to by the
current mode.

=head3 hashkey_database_name

This is a string that identifies the 'Database Name' part of the SBToolsDB
hashkey that points to the managed DSNs.  Usually, this is set by the
implementing class.

=head3 location

Location should be the value of $ENV{LOCATION}.  If it is not set, the value of
$ENV{SBTOOLS_DATABASE_LOCATION} is parsed to get the region.  If that fails, the
value returned by sb_location::WhereIsLocalHost() is used.

Note that location can be overridden when the connection is instantiated.

=head3 location_production_hashkey

The key that identifies the DSN structure of this connection for production
environments.  Usually, this does not need to be overridden.  The default value
is a concatentation of the location and hashkey_database_name attributes.

=head3 location_staging_hashkey

The key that identifies the DSN structure of this connection for staging (and
testing) environments.  Usually, this does not need to be overridden.  The
default value is a concatentation of the location and hashkey_database_name
attributes along with the string 'Test'.

=head3 mode

Connection objects can be in one of two modes: production or staging.  This
controls which database environment is returned by the C<db> attribute.

This can be set manually.  If not, mode is set according to the following
sources of information:

=over 4

=item $ENV{SBTOOLS_DATABASE_MODE}

=item $ENV{SBTOOLS_DATABASE_LOCATION}

=item $ENV{LOCATION} is set; default to 'production'

=back

=head3 use_dbi_cache

A boolean attribute that determines whether the DBI handle will use the
'connect_cached' option, which can be helpful in certain environments (like CGI
web applications).  The default value 0, which does not use connection caching
at all.

=head2 Methods

=head3 database

Retuns the name of the MySQL database associated with the current mode.

=head3 host

Retuns the name of the MySQL database host associated with the current mode.

=cut
    
1;
