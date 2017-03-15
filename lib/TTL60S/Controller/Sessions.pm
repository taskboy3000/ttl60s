package TTL60S::Controller::Sessions;
use Mojo::Base 'Mojolicious::Controller';

# This action will render a template
sub create {
  my $self = shift;
  my $app = $self->app;
  my ($email, $password) = ($self->param("email"), $self->param("password"));
  
  # try to validate the user
  if (my $id = $app->authenticate($email, $password)) {
      $app->log->debug("Yes!");
      $self->session("user_id" => $id);
      
      # redirect to game dashboard
      return $self->redirect_to($self->url_for("dashboard"));
  } else {
      $app->log->debug("No!");
      
  }

}

1;
