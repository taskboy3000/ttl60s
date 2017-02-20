package DB::Tablename;
use strict;
use warnings;

# @EXPORT = qw();  for sbcheckuses
use CPAN::sb_cpan_lib;

#-------------------------------------------------------------------------------
# Import
#-------------------------------------------------------------------------------
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
	die("No compatible with Roles.");
    }

    # Create enriched attribute accessors for columns
    # store the list of columns
    my $table_name = sub {
	my ($name, %attrs) = @_;

	do {
	    no strict 'refs';
	    *{"${target}::table_name"}  = sub { $name };
	};

	return;
    };

    # Inject a subroutine into the caller
    do {
	no strict 'refs';
	*{"${target}::tableName"}  = $table_name;
    };

    return;
} # end sub import

1;
