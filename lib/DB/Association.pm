package DB::Association;
use strict;
use warnings;

sub import {
    my (undef, @import) = @_;

    my $target = caller();

    for my $needed_method (qw/has with around/) {
	next if $target->can($needed_method);
	# Can't find $needed_method() in '$target'. Load Moo first";
	return;
    }

    my $has = $target->can('has');

    my @target_isa;
    do {
	no strict 'refs';
	@target_isa = @{"${target}::ISA"};
    };

    unless (@target_isa) {
	die("No compatible for Roles.");
    }

    # create the storage in the target package, if needed
    do {
	no strict 'refs';

	# A utilty function to produce the ISA list
	# A lexically-scoped code ref will not polute the namespace of callers
	my $object_parents = sub {
	    my ($class) = @_;
	    return unless $class;

	    my $get_parents = sub {
		my ($class) = @_;
		return eval "@" . $class . "::ISA";
	    };

	    my @pending = (ref $class || $class);
	    my @resolved = @pending;
	    while (my $package = pop @pending) {
		my @new = $get_parents->($package);
		last unless @new;
		push @pending,  @resolved;
		push @resolved, @new;
	    }

	    return @resolved;
	};

	# If the class variable has not been defined, define it now
	if (! %{"${target}::FOREIGN_KEYS}"} ) {
	    %{ "${target}::FOREIGN_KEYS}" } = ();
	}

	# Create an accessor for this storage
	*{"${target}::foreign_keys"} = sub {
	    my ($class) = @_;

	    if (ref $class) {
		$class = ref $class;
	    }

	    my $keys;
	    do {
		no strict 'refs';
		# If the class variable has not been defined, define it now
		if (! %{"${class}::FOREIGN_KEYS}"}) {
		    %{"${class}::FOREIGN_KEYS}"} = ();
		}
		$keys = \%{"${class}::FOREIGN_KEYS}"};
	    };

	    return $keys;
	};

	# create an accessor method with business logic used by belongs_to and
	# has_many
	*{"${target}::foreign_key_for"} = sub {
	    my ($class, $type, $related_class, $column) = @_;

	    return unless $type;
	    return unless $related_class;

	    $related_class = (ref $related_class || $related_class);

	    # Remember, this linkage is set at model definition time
	    if (defined $column) {
		if (!exists $class->foreign_keys->{$related_class}) {
		    $class->foreign_keys->{$related_class} = {};
		}
		$class->foreign_keys->{$related_class}->{$type} = $column;
	    }

	    # Subclassed models will identify differently, but we
	    # can find the ancestral link.
	    for my $package ($object_parents->($related_class)) {
		if (exists $class->foreign_keys->{$package}->{$type}) {
		    return $class->foreign_keys->{$package}->{$type};
		}
	    }

	    return;
	};

	*{"${target}::foreign_key_foreign_column"} = sub {
	    shift->foreign_key_for('foreign', @_);
	};

	*{"${target}::foreign_key_our_column"} = sub {
	    shift->foreign_key_for('our', @_);
	};
    };

    # attrs
    #   related:
    #   join_conditions
    #   filter_conditions
    my $belongs_to = sub {
	my ($name, %attrs) = @_;

	die("assert - missing 'join_conditions'")
	    unless exists $attrs{join_conditions};

	my $related_class          = $attrs{related_to};
	my $join_conditions_APtr   = $attrs{join_conditions};
	my $filter_conditions_APtr = [];

	if (exists $attrs{filter_conditions}) {
	    $filter_conditions_APtr = $attrs{filter_conditions};
	}

	# Foreign key analysis
	my (undef, $our_column) =
	    split(/\./, $join_conditions_APtr->[0]->[0], 2);
	$target->foreign_key_our_column($related_class => $our_column);

	my (undef, $foreign_column) =
	    split(/\./, $join_conditions_APtr->[0]->[1], 2);
	$target->foreign_key_foreign_column($related_class => $foreign_column);

	# Install foreign_keys hash and the accessor method
	do {
	    no strict 'refs';
	    *{"${target}::$name"} = sub {
		# Why am I getting self again?
		# 1. This is a method definition
		# 2. The current object reference is always passed into methods
		#    at invocation time
		# 3. This object reference will be in a *different* state than the
		#    $self reference as it appears at *BUILD* time
		#
		# Without getting the current reference, you get a closure with the
		# older reference, which leads to subtle and hard to understand bugs.
		my ($self) = @_;
		$self->get_associated_objects(
		    related_class     => $related_class,
		    has_many          => 0,
		    join_conditions   => $join_conditions_APtr,
		    filter_conditions => $filter_conditions_APtr,
		    )

	    };
	};
	return;
    };

    my $has_many = sub {
	my ($name, %attrs) = @_;

	die("assert - missing 'join_conditions'")
	    unless exists $attrs{join_conditions};

	my $related_class          = $attrs{related_to};
	my $join_conditions_APtr   = $attrs{join_conditions};
	my $filter_conditions_APtr = [];

	if (exists $attrs{filter_conditions}) {
	    $filter_conditions_APtr = $attrs{filter_conditions};
	}

	# Foreign key analysis
	my (undef, $our_column) =
	    split(/\./, $join_conditions_APtr->[0]->[0], 2);
	$target->foreign_key_our_column($related_class => $our_column);

	my (undef, $foreign_column) =
	    split(/\./, $join_conditions_APtr->[0]->[1], 2);
	$target->foreign_key_foreign_column($related_class => $foreign_column);

	# Install foreign_keys hash and the accessor method
	do {
	    no strict 'refs';
	    *{"${target}::$name"} = sub {
		# Why am I getting self again?
		# 1. This is a method definition
		# 2. The current object reference is always passed into methods
		#    at invocation time
		# 3. This object reference will be in a *different* state than the
		#    $self reference as it appears at *BUILD* time
		#
		# Without getting the current reference, you get a closure with the
		# older reference, which leads to subtle and hard to understand bugs.
		my ($self) = @_;
		$self->get_associated_objects(
		    related_class     => $related_class,
		    has_many          => 1,
		    join_conditions   => $join_conditions_APtr,
		    filter_conditions => $filter_conditions_APtr,
		    )

	    };
	};
	return;
    };

    do {
	no strict 'refs';
	*{"${target}::belongs_to"} = $belongs_to;
	*{"${target}::has_many"}   = $has_many;
    };

    return;
} # end sub import


1;
