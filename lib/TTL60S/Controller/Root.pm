package TTL60S::Controller::Root;
use Mojo::Base 'Mojolicious::Controller';

# This action will render a template
sub index {
  my $self = shift;

  my %vars; 
  $self->render(%vars);
}

1;
