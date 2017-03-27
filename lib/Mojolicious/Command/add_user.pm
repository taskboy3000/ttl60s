package Mojolicious::Command::add_user;
use Mojo::Base 'Mojolicious::Command';
use Mojo::Util 'getopt';
use DB::Model::User;
has description => 'Add a new user account';

has usage => sub { shift->extract_usage };

sub run {
    my ($self, @args) = @_;

    my ($email, $password);
    my %params = (
                  'e=s' => \$email,
                  'p=s' => \$password,
                 );

    getopt(\@args, %params);
    unless ($email) {
        die($self->usage);
    }

    my $U = DB::Model::User->new;
    my $users = $U->find(email => $email);

    my $user;
    if (@$users) {
        print "An account with '$email' already exists\n";
        $user = $users->[0];
    } elsif ($password) {
        # create this user
        $U->email($email);
        $U->password_hash("changeme");
        my $id = $U->save;
        $user = $U->get($id);
    } else {
        print "No such user '$email'\n";
        return;
    }
 
    # Update the pasword for the account found
    if ($password) {
        print "Updating password\n";
        $user->password_hash($U->hash($password));
        $user->save;
    }

    for my $column (sort @{$U->columns}) {
        printf("%25s => %s\n", $column, $user->$column());
    }
    return 1;
}


1;

=pod

=head1 SYNOPSIS

  Usage: ttl60s add_user [OPTIONS]

  Options:
   -e [email] Required
   -p [password] If missing, simply print out the user record
 
=cut
