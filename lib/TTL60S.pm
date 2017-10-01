# -*- cperl -*-
package TTL60S;
use Mojo::Base 'Mojolicious';
use Mojolicious::Plugin::MyAuth;
use DB::Model::User;
use File::Slurp;

# This method will run once at server start
sub startup {
    my $self = shift;

    eval { $self->init_secret(); } or do {
        $self->app->log->debug($@);
    };

    $self->sessions->default_expiration(86400);
    $self->sessions->cookie_name("ttl60s");

    $self->plugin(
        'Mojolicious::Plugin::MyAuth' => {
            autoload_user => 1,
            session_key   => 'user_id',
            load_user     => \&load_user,
            validate_user => \&validate_user,
        }
    );
    $self->make_routes;
}

sub make_routes {
    my ($self) = @_;
    my $r = $self->routes;
    $r->get("/")->to("Root#index");
    $r->post("/login")->to("Sessions#create");
    $r->delete("/logout")->to("Sessions#destroy");
    $r->get("/dashboard")->over( authenticated => 1 )->to("Dashboards#index");
    $r->any("*")
        ->to( cb => sub { my ($self) = @_; $self->redirect_to("/") } );
}

sub load_user {
    my ( $c, $uid ) = @_;
    my $app = $c->app;
    my $U   = DB::Model::User->new;

    if ($uid) {
        return $U->get($uid);
    }

    $app->log->warn("NO USER FOR ID $uid\n");
    return;
}

sub validate_user {
    my ( $c, $email, $password, $extradata ) = @_;
    my $app = $c->app;

    my $U     = DB::Model::User->new;
    my $hash  = $U->hash($password);
    my $found = $U->find( email => $email, password_hash => $hash );
    my $uid   = -1;

    if (@$found) {
        return $found->[0]->id;
    }

    $app->log->warn("Cannot find email '$email' with pw hash '$hash'");
    return $uid;
}

sub init_secret {
    my ($self) = @_;

    my $secrets_file = "$ENV{APP_HOME}/ttl60s.secret";

    if ( -e $secrets_file ) {
        my @contents = read_file($secrets_file);
        $self->app->secrets( \@contents );
    }
}

1;
