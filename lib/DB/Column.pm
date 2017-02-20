package DB::Column;
use strict;
use warnings;

#------------------------------------------------------------------------------
# Import
#------------------------------------------------------------------------------
# XXX -- auto add columns id, updated_at, created_at??
# XXX explain import, why we are using it, update docs
# based on: http://cpansearch.perl.org/src/CELOGEEK/MooX-Options-4.018/lib/MooX/Options.pm
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

    # Create enriched attribute accessors for columns
    # store the list of columns
    my $column = sub {
	my ($name, %attrs) = @_;
	$attrs{is}      = 'rw';
	$attrs{trigger} = sub {
	    # This is defined in model.pm
	    shift->set_attribute_dirty($name);
	};
	$has->($name => %attrs);
	do {
	    no strict 'refs';
	    push @{"${target}::_COLUMN_NAMES"}, $name;
	};
	return;
    };

    # An accessor to get all columns
    my $columns = sub {
	my @columns = do {
	    no strict 'refs';
	    @{"${target}::_COLUMN_NAMES"};
	};
	return \@columns;
    };

    # Inject a column() subroutine into the caller
    do {
	no strict 'refs';
	*{"${target}::column"}  = $column;
	*{"${target}::columns"} = $columns;
    };

    return;
} # end sub import

1;
