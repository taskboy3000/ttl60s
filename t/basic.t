use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new('TTL60S');
$t->get_ok('/')->status_is(200)->content_like(qr/TTL:\s+60s/i);

done_testing();
