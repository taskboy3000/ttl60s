package DB::SchemaManager;
use strict;
use warnings;

use File::Slurp ('read_file');
use Moo::Role;

#------------------------
# Attributes
#------------------------
has applied_changes    => ('is' => 'rw', default => sub { [] });
has changes_directory  => (is => 'ro', lazy => 1, builder => 1);
has connection         => (is => 'ro', lazy => 1, builder => 1);
has location           => (is => 'rw');
has last_failed_change => ('is' => 'rw'); 
has versions           => (is   => 'ro', lazy => 1, builder => 1);

#----------------------
# Builders
#----------------------
sub _build_changes_directory {"./schema"}

sub _build_connection {
    die("Override with 'around _build_connection => sub{}'");
} # end sub _build_connection


sub _build_versions {
    my ($self) = @_;

    return [] unless $self->has_version_table;

    my $sql = sprintf("SELECT * FROM schema_versions ORDER BY filename ASC");
    my $sth = $self->connection->db->prepare($sql);
    unless ($sth->execute()) {
	warn($sth->{Statement});
    }

    return $sth->fetchall_arrayref({});
} # end sub _build_versions

#-------------------------------------------------------------------------------
# Methods
#-------------------------------------------------------------------------------
sub upgrade {
    my ($self, $dry_run) = @_;
    my @changes = $self->get_change_files();

    pop @{ $self->applied_changes } while @{ $self->applied_changes };

  CHANGE:
    for my $change (@changes) {
	next CHANGE if $self->is_change_applied($change);

	# Mostly for debugging
	if ($dry_run) {
	    print "Pending change: $change\n";
	    next CHANGE;
	}

	if (!$self->apply_change($change)) {
	    $self->last_failed_change($change);
	    warn("Failed to apply change file '$change'");
	    return;
	}

	push @{ $self->applied_changes }, $change;
    }

    return 1;
} # end sub upgrade


sub is_change_applied {
    my ($self, $file) = @_;
    my $db = $self->connection->db;

    if (!$self->has_version_table) {
	$self->install_version_table;
    }

    my $sql = sprintf("SELECT COUNT(*) FROM schema_versions WHERE filename = %s",
		      $db->quote($file));

    my $sth = $db->prepare($sql);

    unless ($sth) {
	warn($sth->errstr);
        $db->disconnect;
	return;
    }

    unless ($sth->execute) {
        $db->disconnect;
	die($sth->{Statement});
    }

    my $row = $sth->fetchrow_arrayref;
    $sth->finish;
    $db->disconnect;

    return $row->[0];
} # end sub is_change_applied


sub apply_change {
    my ($self, $file) = @_;
    my $db = $self->connection->db;

    my $dir = $self->changes_directory;

    my $sql = read_file("$dir$file");
    return if !$db->do($sql);

    $sql = sprintf(
	        qq[INSERT INTO schema_versions
                     (filename, created_at) VALUES (%s, CURRENT_TIMESTAMP)],
	$db->quote($file)
	);

    $db->do($sql);
    $db->commit;
    return 1;
} # end sub apply_change


sub get_change_files {
    my ($self) = @_;

    my @files;
    my $dir;

    if (opendir $dir, $self->changes_directory) {
      DIR_ENTRY:
	while (my $file = readdir $dir) {
	    next DIR_ENTRY if -d $file;
	    push(@files, $file) if $self->validate_change_file_name($file);
	}
	closedir $dir;
    } else {
	die("Cannot read SQL changes directory: " . $self->changes_directory);
    }

    return sort @files;
} # end sub get_change_files


# e.g. YYYYMMDD_XX_.+?.sql
sub validate_change_file_name {
    my ($self, $filename) = @_;
    $filename =~ /^\d{8}_\d{2}.+?\.sql$/;
} # end sub validate_change_file_name


# Add the schema_version table
sub install_version_table {
    my ($self) = @_;

    my $db         = $self->connection->db;
        my $create_sql = qq[CREATE TABLE schema_versions (
id INTEGER PRIMARY KEY autoincrement,
filename VARCHAR(255) NOT NULL,
created_at DATETIME,
UNIQUE (`filename`)
)];
    $db->do("DROP TABLE IF EXISTS schema_versions");
    $db->do($create_sql) || die($db->errstr);
    $db->commit;
    return 1;
} # end sub install_version_table


sub has_version_table {
    my ($self) = @_;
    my $db = $self->connection->db;
    eval {
	my $result = $db->selectall_arrayref("SELECT 1 FROM schema_versions");
	$result && $result->[0] && $result->[0]->[0];
    } or do {
	return;
    };

    return 1;
} # end sub has_version_table


# Report the latest current change
sub current_version {
    my ($self) = @_;

    return unless $self->has_version_table;

    my $db = $self->connection->db;

    my $sql = q[SELECT * FROM schema_versions
       WHERE filename = (SELECT MAX(filename) FROM schema_versions)];

    my $sth = $db->prepare($sql);
    unless ($sth->execute) {
	die($sth->{Statement});
    }

    return $sth->fetchrow_hashref;
} # end sub current_version


sub available {
    my ($self) = @_;
    my $rc = eval {
	my $db = $self->connection->db;
        $db->disconnect;
    };
    return defined $rc;
}

sub VARCHAR { }
sub MAX     { }

=pod

=head1 NAME

DB::SchemaManager - A Moo Role for schema_managers

=head1 SYNOPSIS

  package DB::SchemaManager::ttl60s;

  use File::Slurp ('read_file');
  use DB::Connection::ttl60s;
  use Moo;
  with 'DB::SchemaManager';

  around _build_connection => sub {
    my ($original, $self) = @_;
    DB::Connection::ttl60s->new(mode => $self->mode);
  };

  around _build_changes_directory => sub {

    return "$ENV{APP_HOME}/schema/";
  };

  1;

And later, to actually commit changes to the database:

  DB::SchemaManager::ttl60s->new->upgrade();

=head1 DESCRIPTION

This Moo Role to faciliate making schema changes on a particular
C<DB::Connection> class.

Schema changes are represented as files on disk that include only one complete
SQL statment.  The names of the files determine the order in which the changes
are applied to the associated database.  The order is strictly ascii-betical.

To create a new schema_manager class, simply create a new Moo class that
implements the <DB::SchemaManager> role, which includes overriding the
builder routines for connection and changes_directory.

=head2 Attributes

=head3 connection

Returns the C<DB::Connection> object for this object.

=head3 changes_directory

This is the full path to the directory containing all the change files.  As a
best practice, schema files should be kept in
$ENV{APP_HOME}/schema/[DATABASE_NAME/.  Here is an example directory listing
of etc/schemas/trackers/:

20170220_01_create_users.sql

=head3 versions

This is an array reference to zero or more hash references that describe changes
that have already been applied.  The format of the returned version structure
is:

  {
    id => "An integer"
    filename => "The basename of the change file"
    created_at => "The datestamp of when this record was created"
  }

=head3 mode

Connection objects can be in one of two modes: production or staging.  This
controls which database environment is returned by the C<db> attribute.

=head2 Methods

=head3 apply_change($change_file)

This is the routine users of the schema_manager are most likely to use.

For all the changes found in the change directory, apply any changes which have
not already been applied.  Fatals on any change that cannot be applied (e.g. the
change file contains a syntax error).

Returns 1 on success.

=head3 current_version()

Returns the version record of the last successful change. See the C<versions>
attribute for structure details.

=head3 get_change_files()

Returns the sorted list of all change files in the change directory.

=head3 has_version_table()

Returns 1 if the schema_versions table exists in the database of the associated
connection.

=head3 install_version_table()

Installs the schema_versions table into the database associated with the
configured connection.  This is an internal routine and most users will not need
to call it explicitly.

=head3 is_change_applied($change_file)

This is a boolean that indicates whether this change has been applied to the
database.

=head3 upgrade($dry_run)

This is the work-horse method in which most users will be interested.  It
marshalls all the pending SQL changes and attempts to apply them.

If passed in a true value for $dry_run, apply_changes merely reports which
changes it would have tried to apply that have not already been applied
previously.

=head3 validate_change_file_name()

A routine that inspects the base filename of the change file to ensure it
matches the desired naming convention, which is:

  YYYYMMDD_XX.+?.sql

It is recommended that schema-changing SQL use conventions like

=over 4

=item  20160922_create_trackers.sql

=item  20160922_alter_trackers.sql

=item  20160922_drop_trackers.sql

=back

=cut

1;
