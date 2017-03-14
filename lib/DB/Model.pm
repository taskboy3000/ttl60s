package DB::Model;
use strict;
use warnings;

use Moo;

#-------------------------------------------------------------------------------
# Attributes
#-------------------------------------------------------------------------------
has dirty_attributes => (is => 'ro', lazy => 1, builder => 1);
has connection   => (is => 'ro', lazy => 1, builder => 1);

#------------------------------------------------------------------------------
# Builders
#------------------------------------------------------------------------------
sub BUILD {
    my ($self, $args) = @_;

    $self->reset_dirty_attributes unless $self->id;
} # end sub BUILD


sub _build_connection {
    die "Needs to be overriden with around _build_connection => sub {}";
}


sub _build_dirty_attributes {
    my ($self) = @_;
    my %attrs = map { $_ => 0 } @{$self->columns};
    return \%attrs;
}

#------------------------------------------------------------------------------
# Methods
#------------------------------------------------------------------------------

# Just the last part of the package name, lower-cased
sub short_name {
    my ($self) = @_;
    my $class = ref $self;
    my @parts = split(/::/, $class);
    my $last = $parts[-1];

    # camel case it
    $last =~ s{([a-z])([A-Z])}{ $1 . "_" . $2 }eg;

    # all lower-case
    return lc $last;
} # end sub short_name


#------------------------------------------------
# Object <-> Data structure conversion routines
#------------------------------------------------

sub to_model {
    my ($self, $row_structure) = @_;
    my $class = ref $self;

    # Convert 'related.X' or 'self.Y' keys to 'X' and 'Y' keys
    my @keys = keys %$row_structure;
    for my $key (@keys) {
	if ($key =~ /^(?:related|self)\.(\S+)$/) {
	    # delete the old key, but save the value in the new key
	    $row_structure->{$1} = delete $row_structure->{$key};
	}
    }

    my %params = map { $_ => $row_structure->{$_} } @{$self->columns};
    my $model = $class->new(%params);
    $model->reset_dirty_attributes;
    return $model;
} # end sub to_model


sub to_hash {
    my ($self) = @_;

    my %hash;
    for my $a (@{ $self->columns}) {
	$hash{$a} = $self->$a();
    }

    return %hash;
} # end sub to_hash


# Called by JSON to properly serialize this object
sub TO_JSON {
    my ($self) = @_;
    return { $self->to_hash() };
} # end sub TO_JSON


#--------------------------------------------
# CRUD operations
#--------------------------------------------
sub clone {
    my ($self) = @_;
    my $new = $self->new($self->to_hash());

    my @clear = qw(id created_at updated_at);
    for my $attr (@clear) {
	$new->$attr("");
    }

    return $new;
}


sub get {
    my ($self, @ids) = @_;
    return unless @ids;

    my $db  = $self->connection->db;
    my $sql = sprintf("SELECT * FROM `%s` WHERE id IN (%s)",
		      $self->table_name, join(",", @ids));

    my $sth = $db->prepare($sql);
    unless ($sth->execute) {
	warn($sth->{Statement});
	return;
    }

    my @found;
    while (my $row = $sth->fetchrow_hashref) {
	my $model = $self->to_model($row);
	push @found, $model;
    }
    $db->commit();

    return wantarray ? @found : $found[0];
} # end sub get


# Given a hash a column names => values,
# return a fully quoted where clause
sub build_criteria {
    my ($self) = shift;
    my (%args) = (@_); # assume all of these are column => value pairs

    my $db  = $self->connection->db;
    my $sql = "";

    my @pairs;
    while (my ($column, $value) = each %args) {
	next if substr($column, 0, 1) eq "_";
	if (ref $value eq 'SCALAR') {
	    push @pairs, sprintf("(%s LIKE '%%%s%%')", $column, $$value);
	} else {
	    push @pairs, sprintf("(%s = %s)", $column, $db->quote($value));
	}
    }

    if (@pairs) {
	$sql .= " WHERE " . join(" AND ", @pairs);
    }

    return $sql;
} # end sub build_criteria


sub join_criteria {
    my ($self, $join_thing) = @_;
    return '' unless $join_thing;

    my $join_obj;
    if (ref $join_thing) {
	$join_obj = $join_thing;
    } else {
	eval "require $join_thing";
	$join_obj = $join_thing->new;
    }

    if (!$self->foreign_key_foreign_column($join_obj)
	|| !$self->foreign_key_our_column($join_obj)) {
	die(sprintf("assert - do not know how '%s' is related to '%s'",
		    (ref $join_obj),
		    (ref $self)
	    ));
    }

    my @on_conditions = sprintf("%s.%s = %s.%s",
				$join_obj->table_name,
				$self->foreign_key_foreign_column($join_obj),
				$self->table_name,
				$self->foreign_key_our_column($join_obj)
	);
    # Maybe add a general mechanism for additional on conditions later

    return sprintf(" LEFT JOIN %s ON %s ",
		   $join_obj->table_name,
		   join(" AND ", @on_conditions));

}


sub count {
    my ($self) = shift;
    my (%args) = (@_); # assume all of these are column => value pairs

    my $db = $self->connection->db;
    my $sql = sprintf("SELECT COUNT(*) FROM %s", $self->table_name);

    $sql .= $self->join_criteria($args{_opts}->{join});

    if (my $where = $self->build_criteria(%args)) {
	$sql .= $where;
    }

    warn($sql) if $ENV{TC_DEBUG};

    my $sth = $db->prepare($sql);
    unless ($sth->execute) {
        warn(sprintf("DEBUG> %s\n", $sth->errstr));
	warn($sth->{Statement});
	return;
    }

    my $rows = $sth->fetchall_arrayref();
    $db->commit();

    # Return a list of models
    return $rows->[0]->[0];
} # end sub count


# Some classes will want to override this for non-equal criteria
sub find {
    my ($self) = shift;
    my (%args) = (@_); # assume all of these are column => value pairs

    my $db = $self->connection->db;

    my @raw_fields = ('*');

    my @fields = map { sprintf("%s.%s", $self->table_name, $_) } @raw_fields;

    my $sql =
	sprintf("SELECT %s FROM `%s`", join(",", @fields), $self->table_name);

    $sql .= $self->join_criteria($args{_opts}->{join});

    if (my $where = $self->build_criteria(%args)) {
	$sql .= $where;
    }

    my $order = "";
    if (exists $args{_opts}->{order}) {
	$order = sprintf(" ORDER BY %s ", $args{_opts}->{order},);
    }
    $sql .= $order;

    my $limit = "";
    if (defined $args{_opts}->{page}) {
	$args{_opts}->{page_size} ||= 25;
	$limit = sprintf(
	    " LIMIT %d OFFSET %d ",
	    $args{_opts}->{page_size},
	    ($args{_opts}->{page} * $args{_opts}->{page_size})
	    );
    }

    $sql .= $limit;

    my $sth = $db->prepare($sql);

    warn("$sql\n") if $ENV{TC_DEBUG};

    unless ($sth->execute) {
        warn(sprintf("DEBUG> %s\n", $sth->errstr));
	warn($sth->{Statement});
	return;
    }

    my $rows = $sth->fetchall_arrayref({});
    $db->commit();

    # Return raw hashes
    if ($args{_opts}->{no_objects}) {
	return $rows;
    }

    return [ map { $self->to_model($_) } @$rows ];
} # end sub find


sub get_distinct_column_values {
    my ($self, $field, $filterHPtr) = @_;
    return unless $field;

    my $db  = $self->connection->db;

    my $criteria = "";
    if ($filterHPtr) {
	$criteria = $self->build_criteria(%$filterHPtr);
    }

    my $sql = sprintf("SELECT DISTINCT(%s) FROM %s %s ORDER BY %s",
		      $field, $self->table_name, $criteria, $field);

    warn($sql) if $ENV{TC_DEBUG};

    my $sth = $db->prepare($sql);
    unless ($sth->execute) {
        warn("DEBUG> " . $sth->errstr . "\n");
	warn($sth->{Statement});
	return;
    }

    my @values;
    while (my $ar = $sth->fetchrow_arrayref) {
	push @values, $ar->[0];
    }

    return \@values;
} # end sub get_distinct_column_values


# Returns a structure suitable for paging results
# { total_results => INT, # total elements in this search result
#   total_pages   => INT, # total pages in this result (0-based list)
#   page_size     => INT, # results per page
#   current_page  => INT, # current page
#   results       => {},  # the models found by criteria
# }
sub paginated_find {
    my ($self) = shift;
    my %args = @_;

    $args{_opts}->{page_size} ||= 25;
    $args{_opts}->{page}      ||= 0;

    # get a count for the total search
    my $total = $self->count(%args);
    my $found = $self->find(%args);

    my $total_pages = int($total / $args{_opts}->{page_size});
    if ($total % $args{_opts}->{page_size} != 0) {
	$total_pages += 1;
    }

    my $results = {
	page_size     => $args{_opts}->{page_size},
	current_page  => $args{_opts}->{page},
	total_pages   => $total_pages,
	total_results => $total,
	results       => $found,
    };

    return $results;
} # end sub paginated_find


sub delete {
    my ($self, $id) = @_;
    $id ||= $self->id;
    return unless $id;

    my $db  = $self->connection->db;
    my $sql = sprintf("DELETE FROM `%s` WHERE id=%s", $self->table_name, $id);
    my $sth = $db->prepare($sql);
    warn("$sql\n") if $ENV{TC_DEBUG};
    unless ($sth->execute) {
        warn(sprintf("DEBUG> %s\n", $sth->errstr));
	warn($sth->{Statement});
	return;
    }

    $db->commit();
    return 1;
} # end sub delete


sub save {
    my ($self) = @_;

    my (%args) = $self->to_hash;

    my $db = $self->connection->db;
    delete $args{'updated_at'}; # DB handles updating this field

    my $id = delete $args{id};

    my $sql = "";
    if ($id) {
	delete $args{'created_at'}; # Never update created_at

	$sql = sprintf("UPDATE `%s`", $self->table_name);
	my @pairs;
	while (my ($column, $value) = each %args) {
	    next unless defined $value;
	    next unless $self->is_attribute_dirty($column);
	    push @pairs, sprintf("`%s` = %s", $column, $db->quote($value));
	}
	push @pairs, "`updated_at` = CURRENT_TIMESTAMP";

	if (@pairs) {
	    $sql .= " SET " . join(", ", @pairs);
	    $sql .= sprintf(" WHERE id=%d", $id);
	}

    } else {
	for ('updated_at', 'created_at') {
	    delete $args{$_};
	}

	# Dirty attribute check is meaningless here
	my (@columns, @values);
	while (my ($key, $value) = each %args) {
	    next unless defined $value;
	    push @columns, qq[`$key`];
	    push @values,  $db->quote($value);
	}

	push @columns, 'created_at',        'updated_at';
	push @values,  'CURRENT_TIMESTAMP', 'CURRENT_TIMESTAMP';

	$sql = sprintf(
	    "INSERT INTO `%s` (%s) VALUES (%s)",
	    $self->table_name,
	    join(", ", @columns),
	    join(", ", @values)
	    );
    }

    warn("$sql\n") if $ENV{TC_DEBUG};

    my $sth = $db->prepare($sql);
    unless ($sth->execute) {
        warn(sprintf("DEBUG> %s\n", $sth->errstr));
	warn($sth->{Statement});
	return;
    }

    # Need to get the new ID before the commit
    $self->id($id || $db->last_insert_id(undef, undef, 'users', 'id'));

    $db->commit; # Resets the insertid
    $self->reset_dirty_attributes;

    return $self->id;
} # end sub save


# Efficiently update multiple columns in multiple rows with the same values
sub mass_update {
    my ($self, $ids, $attrs) = @_;
    return unless @$ids;

    my $db = $self->connection->db;

    my @pairs;
  ATTRS:
    while (my ($column, $value) = each %$attrs) {
	next ATTRS unless $column;
	next ATTRS unless $value;

	push @pairs, sprintf("`%s` = %s", $column, $db->quote($value));
    }

    return unless @pairs && @$ids;

    my $sql = sprintf(
	"UPDATE `%s` SET %s WHERE id IN (%s)",
	$self->table_name,
	join(", ", @pairs),
	join(", ", @$ids)
	);

    my $sth = $db->prepare($sql);
    unless ($sth->execute) {
        warn(sprintf("DEBUG> %s\n", $sth->errstr));
	warn($sth->{Statement});
	return;
    }

    $db->commit;
    return 1;
} # end sub mass_update


#------------------------------------------------
# Current timestamp functions
#------------------------------------------------
sub db_now {
    my ($self, $offset) = @_;
    return $self->connection->db_now($offset);
} # end sub db_now


sub db_start_of_day {
    my ($self, $ts) = @_;
    return $self->connection->db_start_of_day($ts);
} # end sub db_start_of_day


sub db_end_of_day {
    my ($self, $ts) = @_;
    return $self->connection->db_end_of_day($ts);
} # end sub db_end_of_day


#----------------------------------------------------------
# Associations
#----------------------------------------------------------
# Abstract:
#   This method will not be useful for most consumers of this role.
#   It is called from BUILD to instantiated belongs_to and has_many
#   read-only accessors.
sub get_associated_objects {
    my ($self) = shift;
    my %args = (
	has_many => 0,
	related_class => undef,
	join_conditions => [],
	filter_conditions => [],
	@_
	);

    die "assert" unless ref $args{join_conditions} eq 'ARRAY';
    die "Missing related class name" unless $args{related_class};

    # Bring in the related class
    my $related_class = $args{related_class};
    eval "require $related_class;";
    die "Cannot include '$related_class'" if $@;
    my $related_object = $related_class->new;

    # SELECT related.*
    #   FROM $self->table_name AS me JOIN $related_class AS related ON $joinCondAPtr
    #   WHERE 1=1 AND $filterCondAPtr
    # and then return objects of $related_class
    my @filters = @{$args{filter_conditions}};
    push @filters, [ 1 => 1 ];
    push @filters, [ 'me.id' => ($self->id || -1) ];

    my @join_conditions   = map { sprintf "%s = %s", $_->[0], $_->[1] } @{$args{join_conditions}};
    my @filter_conditions = map { sprintf "%s = %s", $_->[0], $_->[1] } @filters;

    my $db = $self->connection->db;
    my $sql = sprintf("SELECT related.* FROM %s AS me JOIN %s AS related ON %s WHERE %s",
		      $self->table_name,
		      $related_object->table_name,
		      ( join(" AND ", @join_conditions) ),
		      ( join(" AND ", @filter_conditions) ),
	);

    warn("---> $sql\n") if $ENV{TC_DEBUG};

    my $sth = $db->prepare($sql);
    unless ($sth->execute) {
	warn($sth->{Statement});
    }

    my @found;
    while (my $row = $sth->fetchrow_hashref) {
	push @found, $related_object->to_model($row);
    }

    return $args{has_many} ? \@found : $found[0];
}

#-------------------------------------------------
# Attribute caching routines
#-------------------------------------------------
# Mark all of the columns in the cache as clean
sub reset_dirty_attributes {
    my ($self) = @_;
    my $attrs = $self->dirty_attributes;
    for my $attr (keys %$attrs) {
	$attrs->{$attr} = 0;
    }
}


# Given a column name, mark that column as dirty in cache
sub set_attribute_dirty {
    my ($self, $attr) = @_;
    if (exists $self->dirty_attributes->{$attr}) {
	return $self->dirty_attributes->{$attr} = 1;
    }

    return;
}


# Given a column name, determine if the value has been changed since the last fetch
sub is_attribute_dirty {
    my ($self, $attr) = @_;

    if (exists $self->dirty_attributes->{$attr}) {
	return $self->dirty_attributes->{$attr} > 0;
    }
    return;
}


# Returns the list of columns with dirty values
sub get_dirty_attributes {
    my ($self) = @_;

    return grep { $self->is_attribute_dirty($_) } @{$self->columns};
}


# Returns the number of dirty attributes, which can be used as a boolean
sub has_dirty_attributes {
    my ($self) = @_;
    return scalar $self->get_dirty_attributes;
}


#-------------------------------------------------------------------------------
# CLASS METHODS
#-------------------------------------------------------------------------------

1;

=pod

=head1 NAME

DB::Model - A Moo::Role for ORM models

=head1 SYNOPSIS

  # An example of a class using this
  package DB::Model::User;

  use DB::Connection::ttl60s;

  use Moo;

  use DB::Column;
  use DB::Tablename;
  extends 'DB::Model';

  around _build_connection => sub { DB::Connection::ttl60s->new };

  tableName 'ttl60s';

  column 'id';
  column 'name';
  column 'updated_at';
  column 'created_at';

  1;

  # An example of instantiation
  my $U = DB::Model::User->new;

  # An example of fetching all rows in the table
  my $users = $U->find();

  # An example of filtering rows from the table
  my $list = $U->find(name => "Joe");

  # An example of access column data in each model
  for my $user (@$list) {
     printf("ID: %d, name: %s\n", $user->id, $user->host);
  }

  # An example of updating an existing model
  $user->name("general");
  $daemon->save();

  # An example of creating a new model and persisting it
  my $new = DB::Model::User->new(name => "foo");

  if (!$new->id) {
     warn("object is not yet persisted to the data store");
  }

  my $id = $new->save;

  # An example of fetching a particular row with id = 1234
  my $user = $U->get(1234);

  # An example of deleting a model
  $new->delete;


=head1 DESCRIPTION

The goal of any Object-Relational Mapper is to provide a clean way to handle
database-persistent data using native language objects.  The details of how to
connect to the database and all the SQL syntax are hidden behind an API that
provides a consistent interface to row-level data.

Access to data stored in tables happens through a model class that implements
the DB::Model role.  Each model is responsible for mapping column data of a
particular table into an object instance of the model.  Models may also present
methods that act on the entire table.  Typically, application business logic is
often contained in custom methods of the model so that users of the model apply
this business logic consistently across web pages or command line tools.

In additional to faciliating persistance operations (often called Create,
Retrieve, Update and Delete or CRUD), models also help manage the relationship
of one model to others.  Such relationships are the mainspring of SQL.  One
table may have a foreign key into another (such an arrangement is known as a
daughter table).  A row in one table may related to several rows in a different
table.  These relationships can be modeled as L<Associations>.

All ORMs have trade-offs for the convenience they provide.  The first is that
MySQL tables have to follow certain conventions, which are detailed in L<MySQL
Table Conventions>.  The second is that while basic CRUD operations are trivial
and fetching models from related tables is easy, complex fitlering and joins are
outside the scope of this ORM.  In those cases, it is recommended that the
underlying DBI handle (available through C<model->connection->db>) is used in
the typical prepare, execute and fetch pattern.  Doing this will result in raw
perl data structures, unless additional work is done to map these results back
into a model.  The final drawback is the performance impact such a class system
can have on an application.  There are some well-known performance-grading
patterns (such as the N+1 problem) that affect all ORMs.  Each has its own
work-around, but some performance testing is advised here.

=head2 Creating models

Once the database table has been created according to the L<MySQL Table
Conventions>, the model class can be written.  At a minimum, a model author
needs a L<DB::Connection> to the database connecting the desired table, the
name of the table and the names of the columns in that table.  These values are
specified in the appropriate builder routines, which are overriden in the Role
using the around() mechanism.

Additionally, the author may wish to specify L<Associations> to other models,
but this is not required.

=head2 Table Conventions

All tables managed by an DB::Model are expected to have the following fields
with the following definitions:

  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  updated_at DATETIME
  created_at DATETIME

The save method populates updated_at and created_at in expected ways.

=head2 Attributes

These attributes are all read-only and are defined when the model is created.

=over 4

=item columns

This is an array reference of database columns the modeled table has. All lists should
include 'id', 'updated', 'created', although the order does not much matter.

=item connection

This is a L<DB::Connection> object through which the handle to the database
is obtained.

=item table_name

This is the name of the database table that the model represents.

=back

=head2 Methods

The following instance methods are defined for all implementing models.

=head3 new()

Often, called without parameters to return a generic model object.  When
creating a new model, pass in a hash with keys that are columns (omitting 'id',
'updated_at' and 'created_at') along with values that represent the desired data
to be stored.

Returns a model object.

=head3 to_model($row_structure)

Mostly used under the hood, this method takes a hash reference that represents
row data from the modeled table.  It then creates a new model object with the
row data.

=head3 to_hash()

Sometimes, it is desirable to turn models back into a plain Perl hash (for JSON
encoding, for example).  Only meaningful when the current model object is
already holding data retrieved from the database.

=head3 get($id)

Given an ID for a row in the modeled table, return a model populated with data
 fetched from the database.


=head3 get_distinct_column_values($column, $fitlerHPtr)

Given a column name, return an array reference of unique values of that column
from the modeled table. Results are always sorted in ascending order.

An optional $filterHPtr may be passed in.  Such a hashref has keys that are
column names and values that are exactly matched in the table data.  Multiple
keys are ANDed together.

=head3 count(%criteria)

Returns a count of rows matched by the passed in %criteria.  See L<find> to
learn more about the expected structure of this hash.

=head3 find(%criteria)

Returns a list of models that matched the given %criteria.

The %criteria has is composed of keys that are either the names of columns or
the special key "_opts".  The values of keys that are columns are assembled
parts of an SQL WHERE clause that are ANDed together.

If the value of a column is a scalar reference, a LIKE comparison is
constructed.  Otherwise, the comparison is an exacted string match.

The value of the "_opts" key is a hash reference.  The supported keys of that
hash are "order", "page", and "page_size".  The value of an "order" key is
expected to be a column name. The keys "page" and "page_size" are used are
arguments to an SQL LIMIT clause to restrict the number of rows returned, which
page_size is the number of rows returned and page * page_size is the offset into
the rows returned.

=head3 paginated_find(%criteria)

Works identically as L<find> (it calls find() under the hood), but returns a
structure amenable to paging results on a web page.  The returned structure is:

  { page_size     => [INT], # default is 25
    current_page  => [INT], # default 0
    total_pages   => [INT], # how many pages are there for the criteria?
    total_results => [INT], # how many records are there for the criteria?
    results       => \@models, # list of matching models found on this page
  }


=head3 save()

Saves this model's current column values to the database.  If the id attribute
is set, this is an UPDATE operation.  Otherwise, it is an INSERT.

Returns the id of the associated row in either case.

=head3 delete($id)

Given an id or the current value of the id attribute, delete this row from the
database table.  Returns 1 on success.

=head3 db_now($offset)

This is a convenience function that simple returns the current timestamp from
the database using the connection object.  See L<sb_db::connection> for details.

=head3 db_start_of_day($unix_timestamp)

See L<DB::Connection> for details.

=head3 db_end_of_day($unix_timestamp)

See L<DB::Connection> for details.

=head2 Associations

Associations are connections this model has to others.  This association is used
to fetch those related models in an easy way.

There are two types of associations supported by this role: belongs_to and
has_many.

Creating an association is done inside the model class like this:

  package DB::Model::foo
  use Moo;

  use DB::Association;
  use DB::Column;
  use DB::Tablename;
  extends 'DB::Model';

  tableName 'Foo';
  column 'id';

  belongs_to "bar" => (related_to => "DB::Model::bar",
                       join_conditions => [[ "me.bar_id" => "related.id" ]]
                      );

  has_many "bazes" => (related_to => "DB::Model::baz",
                       join_conditions => [[ "me.id" => "related.foo_id" ]]
                      );

  1;

The arguments to both association builder methods is the same:

=over 4

=item method name

A read-only method with this name will be created on the model to fetch the
related objects.

Already, you might see some conventions emerging: plural nouns for has_many,
singular for belongs_to.

=item related class name

This is the name of the class of the related model.  The association returns
this kind of object.

=item list of join conditions

The list of join conditions.

This is an array reference of array references.  Each inner array reference is a
two element list that holds a column name of the current model and a column name
of the related table.

When referring to a column in the model's table, append with "me.".  When
referring to a column in the other table, append the column name with
"related.".


=item list of filter conditions.

The list of filter conditions

This is also an array reference of array references.  Each inner array reference
is a two element array with a column name and a value.  The column name uses the
me vs. related convention.  The match is an exact string match.


=back

At first, associations can get a little confusing.  In the interests of
de-mystifying this, a template of the SQL that is generated by these
associations appears below:

  SELECT related.* FROM [THIS_MODEL_TABLE] AS me
     JOIN [RELATED_MODEL_TABLE] AS related
       ON [JOIN_CONDITIONS]
     WHERE 1=1 [FILTER_CONDITIONS]


=head3 belongs_to

This association is used to return just one related object.  For example, a child
object might want to refer to its parent object using a belongs_to association.

=head3 has_many

This association is used to return the list of related models defined by
join_conditions and filter_conditions.

=cut
