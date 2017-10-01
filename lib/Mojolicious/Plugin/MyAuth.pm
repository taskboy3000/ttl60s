use warnings;
use strict;

package Mojolicious::Plugin::MyAuth;
use Mojo::Base 'Mojolicious::Plugin';
use Data::Dumper;

our $VERSION = '0.01';

sub register {
    my ($self, $app, $args) = @_;

    $args ||= {};

    die __PACKAGE__, ": missing 'load_user' subroutine ref in parameters\n"
        unless $args->{load_user} and ref $args->{load_user} eq 'CODE';

    die __PACKAGE__, ": missing 'validate_user' subroutine ref in parameters\n"
        unless $args->{validate_user} and ref $args->{validate_user} eq 'CODE';

    if (defined $args->{lazy}) {
        warn __PACKAGE__,
            ": the 'lazy' option is deprecated, ",
            "use 'autoload_user' instead\n";

        $args->{autoload_user} = delete $args->{lazy};
    }

    my $autoload_user     = $args->{autoload_user}   // 0;
    my $session_key       = $args->{session_key}     || 'my_auth_data';
    my $our_stash_key     = $args->{stash_key}       || '__my_authentication__';
    my $current_user_fn   = $args->{current_user_fn} || 'current_user';
    my $load_user_cb      = $args->{load_user};
    my $validate_user_cb  = $args->{validate_user};

    my $fail_render = ref $args->{fail_render} eq 'CODE'
       ? $args->{fail_render} : sub { $args->{fail_render} };

    # Unconditionally load the user based on uid in session
    my $user_loader_sub = sub {
        my $c = shift;
	
	my $uid = $app->session($session_key) || $self->{__UID__};

        if (defined($uid)) {
            if (my $user = $load_user_cb->($app, $uid)) {
		return $self->{__USER__} = $user;
            } else {
                # cache result that user does not exist
		$app->log->warn("No user cached in " . $app);
            }
        } else {
	    $app->log->warn("No UID available in stash");
	} 
    };

    # Fetch the current user object from the stash - loading it if
    # not already loaded
    my $user_stash_extractor_sub = sub {
        my ($c, $user) = @_;
	
	$app->log->debug("Start of user extractor in " . $app);
	
        # Allow setting the current_user
        if ( defined $user ) {
	    return $self->{__USER__} = $user;
        }

	# Fetch current user
	$user = $self->{__USER__};
	return $user if defined $user;
	
	# Reload user if no valid user was stashed
	return $user_loader_sub->($app);
    };

    $app->hook(before_dispatch => $user_loader_sub) if $autoload_user;

    $app->routes->add_condition(authenticated => sub {
        my ($r, $c, $captures, $required) = @_;
        my $res = (!$required or $app->is_user_authenticated);

        unless ($res) {
          my $fail = $fail_render->(@_);
          $app->render(%{$fail}) if $fail;
        }
        return $res;
    });

    $app->routes->add_condition(signed => sub {
        my ($r, $c, $captures, $required) = @_;
        return (!$required or $app->signature_exists);
    });

    my $current_user = sub {
        return $user_stash_extractor_sub->(@_);
    };

    $app->helper(reload_user => sub {
        my $c = shift;
        # Clear stash to force a reload of the user object
        delete $app->stash->{$our_stash_key};
        return $current_user->($c);
    });

    $app->helper(signature_exists => sub {
        my $c = shift;
        return !!$app->session($session_key);
    });

    $app->helper(is_user_authenticated => sub {
        my $c = shift;
        return defined $current_user->($c);
    });

    $app->helper($current_user_fn => sub {
	my $c = shift;
	$current_user->($c);
    });

    $app->helper(logout => sub {
        my $c = shift;
        delete $app->stash->{$our_stash_key};
        delete $app->session->{$session_key};
        return 1;
    });

    $app->helper(authenticate => sub {
        my ($c, $user, $pass, $extradata) = @_;
	$app->log->debug("Authenticate's \$app is " . $app);
 
        # if extradata contains "auto_validate", assume the passed username
        # is in fact valid, and auto_validate contains the uid; used for
        # OAuth and other stuff that does not work with usernames and
        # passwords; use this with extreme care if you must

        $extradata ||= {};
        my $uid = $extradata->{auto_validate} //
            $validate_user_cb->($c, $user, $pass, $extradata);
	
        if (defined $uid) {
	    $app->log->debug("Storing UID '$uid' from validate_user_cb in " . $app);
	    $app->session->{$session_key} = $self->{__UID__} = $uid;

            # Clear stash to force reload of any already loaded user object
            delete $app->stash->{$our_stash_key};
            return 1 if defined $current_user->($c);
        } else {
	    $app->log->warn("No UID returned from validate_user_cb");
	}

        return;
    });
}

1;

__END__

