package TTL60S;
use Mojo::Base 'Mojolicious';
use Mojolicious::Plugin::Authentication;
use DB::Model::User;
use File::Slurp;

# This method will run once at server start
sub startup {
  my $self = shift;

  $self->init_secret();

  $self->sessions->default_expiration(86400);
  $self->sessions->cookie_name("ttl60s");

  $self->plugin('authentication' => {
				     autoload_user => 1,
				     session_key => 'user_id',
				     load_user => sub { $self->load_user(@_) },
				     validate_user => sub { $self->validate_user(@_) },
				    });
  $self->make_routes;
}

sub make_routes {
    my ($self) = @_;
    my $r = $self->routes;
    $r->get("/")->to("Root#index");
    $r->post("/login")->to("Sessions#create");
    $r->delete("/logout")->to("Sessions#destroy");
    $r->get("/dashboard")->over(authenticated => 1)->to("Dashboards#index");
}


sub load_user {
    my ($self, $app, $uid) = @_;
    my $log = $self->app->log;
    
    my $U = DB::Model::User->new;

    my $user = $U->get($uid);
    if ($user) {
        $log->debug("Load user $uid -> " . $user->email);
    } else {
        $log->debug("No user found for $uid");
    }

    return $user;
}


sub validate_user {
  my ($self, $app, $email, $password, $extradata) = @_;

  my $U = DB::Model::User->new;
  my $found = $U->find(email => $email, password_hash => $U->hash($password));
  my $uid=-1;

  if (@$found) {      
    $uid = $found->[0]->id;
  }
  return $uid;
}


sub init_secret {
    my ($self) = @_;
    my $secrets_file = "$ENV{APP_HOME}/ttl60s.secret";

    if (-e $secrets_file) {
        my @contents = read_file($secrets_file);
        $self->app->secrets(\@contents);
    }
}

1;
