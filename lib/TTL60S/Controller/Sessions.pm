package TTL60S::Controller::Sessions;
use Mojo::Base 'Mojolicious::Controller';

# This action will render a template
sub create {
  my $self = shift;
  my $app = $self->app;
  my $log = $self->app->log;
  
  my ($email, $password) = ($self->param("email"), $self->param("password"));

  # return $self->no_auth unless $self->valid_csrf;

  # try to validate the user
  warn(sprintf("%s: \$app is %s\n", ref $self, $app));
  if ($app->authenticate($email, $password)) {
    warn("Auth succeeded\n");
    my $user = $app->current_user;
    if ($user) {
      $log->debug(sprintf("Login user[%d]: %s", $user->id, $user->email));
      $self->session("user_id" => $user->id);
      # redirect to game dashboard
      return $self->redirect_to($self->url_for("dashboard"));
    }
    
  }

  $app->log->debug("Bad username/password");
  $self->flash("info" => "Account/password is incorrect");
  return $self->redirect_to($self->url_for("/"));
}


sub destroy {
    my ($self) = @_;

    $self->app->log->debug("Ending web session");
    $self->logout;
    return $self->redirect_to($self->url_for("/"));

}


1;
