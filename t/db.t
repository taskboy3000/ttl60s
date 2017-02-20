use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use DB::SchemaManager::TTL60S;

my $schema = DB::SchemaManager::TTL60S->new;
unless ($schema->available) {
  ok(1, "Schema is unavailable");
}

printf(
       "Connected to %s\n",
       $schema->connection->database,
      );
ok($schema,             "Manager object");
ok($schema->upgrade(1), "Pending changes");

if (1) {
  $schema = DB::SchemaManager::TTL60S->new(mode => "staging");
  my $rc = $schema->upgrade();
  ok($rc, "Commit changes");
  if ($rc) {
    print "Changes committed:\n";
    for my $change (@{ $schema->applied_changes }) {
      printf("  - %s\n", $change);
    }
  }
}


done_testing();
