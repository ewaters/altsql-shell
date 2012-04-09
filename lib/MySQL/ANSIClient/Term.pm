package MySQL::ANSIClient::Term;

use strict;
use warnings;
use Term::ReadLine::Zoid;
use Data::Dumper;

sub new {
	my ($class, $app) = @_;

	my $term = Term::ReadLine::Zoid->new("mysql-color");
	my %self = (
		term => $term,
		app  => $app,
	);
	my $self = bless \%self, $class;

	$self->{app}->log_info("Ctrl-C to reset the line; Ctrl-D on an empty line to exit");

	$term->Attribs->{completion_function} = sub {
		$self->completion_function(@_);
	};

	$term->Attribs->{default_mode} = 'multiline';

	## The user has pressed the 'enter' key.  If the buffer ends in ';' or '\G', accept the buffer
	$term->bindkey('return', sub {
		my $sql = join ' ', @{ $term->{lines} };
		if ($sql =~ m{(;|\\G)\s*$}) {
			$term->accept_line();
		}
		else {
			$term->insert_line();
		}
	});

	return $self;
}

sub readline {
	my $self = shift;

	return $self->{term}->readline('mysqlc> ');
}

sub completion_function {
	my ($self, $word, $buffer, $start) = @_;

	$self->{app}->log_debug("\ncompletion_function: '$word', '$buffer', '$start'");

	return ();
}

1;
