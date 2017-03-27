package DB::Model::User;
use strict;
use warnings;

use Digest::SHA ('sha256_hex');

use Moo;
extends ('DB::Model');

use DB::Tablename;
use DB::Column;
use DB::Association;
use DB::Connection::TTL60S;

around _build_connection => sub { DB::Connection::TTL60S->new };

tableName 'users';
column 'id';
column 'email';
column 'password_hash';
column 'created_at';
column 'updated_at';

#-------------
# Methods
#-------------
sub hash {
    my ($self, $string) = @_;
    return sha256_hex($self->secret . $string);
}

1;
