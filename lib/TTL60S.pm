package TTL60S;
use Mojo::Base 'Mojolicious';
use Mojolicious::Plugin::Authentication;
use DB::Model::User;

# This method will run once at server start
sub startup {
  my $self = shift;

  $self->plugin('authentication' => {
				     autoload_user => 1,
				     session_key => 1,
				     load_user => sub { $self->load_user(@_) },
				     validate_user => sub { $self->validate_user(@_) },
				    });
  $self->sessions->default_expiration(86400);
  $self->make_routes;
  
}

sub make_routes {
    my ($self) = @_;
    my $r = $self->routes;
    $r->get("/")->to("Root#index");
}

sub load_user {
  my ($self, $app, $uid) = @_;
  my $U = DB::Model::User->new;
  return $U->get($uid);
}


sub validate_user {
  my ($self, $app, $email, $password, $extradata) = @_;
  my $U = DB::Model::User->new;
  my $found = $U->find(email => $email, $password_hash => $hash);
  my $uid=-1;
  if (@$found) {
    $uid = $found->[0]->id;
  }
  return $uid;
}


1;
