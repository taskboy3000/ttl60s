use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use DB::SchemaManager::TTL60S;
use DB::Model::User;

my $schema = DB::SchemaManager::TTL60S->new;
unless ($schema->available) {
  ok(1, "Schema is unavailable");
}

ok($schema,             "Manager object");
ok($schema->upgrade(1), "Pending changes");
printf(
       "Connected to %s\n",
       $schema->connection->database,
      );

if (1) {
  $schema = DB::SchemaManager::TTL60S->new;
  my $rc = $schema->upgrade();
  ok($rc, "Commit changes");
  if ($rc) {
    print "Changes committed:\n";
    for my $change (@{ $schema->applied_changes }) {
      printf("  - %s\n", $change);
    }
  }
}


if (0) {
  my $U = DB::Model::User->new;
  ok($U, "User model");
  my $found = $U->find();
  ok($found, "Find works");
  my $new = DB::Model::User->new("email" => 'jjohn@taskboy.com', password_hash => $U->hash('secret'));
  my $id = $new->save();
  ok($id, "Creation: $id");
}

done_testing();
