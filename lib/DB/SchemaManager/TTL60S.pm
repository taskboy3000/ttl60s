package DB::SchemaManager::TTL60S;
use strict;
use warnings;

use DB::Connection::TTL60S;
use Moo;
with 'DB::SchemaManager';

around _build_connection => sub {
    DB::Connection::TTL60S->new
};

around _build_changes_directory => sub {
    return "$ENV{APP_HOME}/schema/";
};

1;
