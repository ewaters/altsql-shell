package MyReceiver;

use strict;
use warnings;
use base 'Pegex::Receiver';
use Data::Dumper;

sub got_name {
	my ($self, $name) = @_;
	printf "Got name %s at position %d\n",
		$name,
		$self->parser->position;
	return { name => $name };
}

sub got_is {
	my ($self) = @_;
	return;
}

sub got_age {
	my ($self, $age) = @_;
	print "Got age $age\n";
	return { age => $age };
}

sub got_age_assertion {
	my ($self, $parts) = @_;
	print Dumper($parts);
	# Collapse the hashes into one
	my %assertion = map {+( %$_ )} @$parts;
	print Dumper(\%assertion);
}

1;
