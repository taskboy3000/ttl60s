package DB::Connection::TTL60S;
use strict;
use warnings;

use Moo;
with 'DB::Connection';

around _build_db_name => sub { "$ENV{APP_HOME}/data/ttl60s.sqlite" };

1;
