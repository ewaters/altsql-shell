#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
	$ENV{PERL_RL} = 'Gnu';
}

use Term::ReadLine;
use Term::ReadLine::Gnu;
use Term::ANSIColor;

my $term = Term::ReadLine->new('Testing');
my $attr = $term->Attribs;
$term->ornaments('');

$term->add_defun(my_bind_cr => sub {
	if ($attr->{line_buffer} =~ m{;\s*$}m) {
		$attr->{done} = 1;
		print "\n";
	}
	else {
		$term->insert_text("\n");
	}
});
$term->add_defun(my_abort => sub {
	print "Abort!\n";
});
$term->bind_key(ord "\r", 'my_bind_cr');
$term->bind_key(ord "\n", 'my_bind_cr');
$term->bind_key(ord "\cc", 'my_abort');

{
	local $SIG{INT} = sub {};
	while (defined (my $input = $term->readline(colored('prompt', 'red') . '> '))) {
		if ($input =~ m{^quit}) {
			last;
		}
	}
}
