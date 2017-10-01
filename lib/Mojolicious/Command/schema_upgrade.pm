package Mojolicious::Command::schema_upgrade;
use Mojo::Base 'Mojolicious::Command';
use Mojo::Util 'getopt';
use DB::SchemaManager::TTL60S;
has description => 'Upgrade schema';

has usage => sub { shift->extract_usage };

sub run {
    my ($self, @args) = @_;

    my $schema = DB::SchemaManager::TTL60S->new;
    unless ($schema->available) {
	die("Schema is unavailable");
    }
    printf(
       "Connected to %s\n",
       $schema->connection->database,
      );

    print "Committing changes\n";
    $schema->upgrade(1);
    print "Changes committed:\n";
    for my $change (@{ $schema->applied_changes }) {
      printf("  - %s\n", $change);
    }

    return 1;
}


1;

=pod

=head1 SYNOPSIS
  Apply schema new changes

  Usage: ttl60s schema_upgrade
 
=cut
