package TTL60S::Controller::Sessions;
use Mojo::Base 'Mojolicious::Controller';

# This action will render a template
sub create {
  my $self = shift;
  my $app = $self->app;
  my ($email, $password) = ($self->param("email"), $self->param("password"));

  # return $self->no_auth unless $self->valid_csrf;

  # try to validate the user
  if (my $id = $app->authenticate($email, $password)) {
      $app->log->debug("Login user[$id]: $email");
      $self->session("user_id" => $id);

      # redirect to game dashboard
      return $self->redirect_to($self->url_for("dashboard"));
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
