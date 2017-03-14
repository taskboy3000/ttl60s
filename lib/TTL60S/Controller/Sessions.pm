package TTL60S::Controller::Sessions;
use Mojo::Base 'Mojolicious::Controller';

# This action will render a template
sub create {
  my $self = shift;

  # try to validate the user
  # create session cookie
  # redirect to game dashboard
  $self->render(%vars);
}

1;
