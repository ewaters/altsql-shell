package MySQL::ANSIClient::Term;

use strict;
use warnings;
use Term::ReadLine::Zoid;
use Data::Dumper;
use JSON::XS;

sub new {
	my ($class, %self) = @_;

	my $term = Term::ReadLine::Zoid->new("mysql-color");
	$self{term} = $term;
	my $self = bless \%self, $class;

	$self->{app}->log_info("Ctrl-C to reset the line; Ctrl-D to exit");

	$term->Attribs->{completion_function} = sub {
		$self->completion_function(@_);
	};

	$term->bindkey('^D', sub {
		print "\n";
		$self->{app}->shutdown();
	});

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

	$self->read_history();

	return $self;
}

sub readline {
	my $self = shift;

	return $self->{term}->readline('mysqlc> ');
}

sub completion_function {
	my ($self, $word, $buffer, $start) = @_;

	#$self->{app}->log_debug("\ncompletion_function: '$word', '$buffer', '$start'");

	my $hash = $self->{app}{autocomplete_entries};
	return () unless $hash;

	my @matches;
	foreach my $key (sort keys %$hash) {
		push @matches, $key if $key =~ m/^$word/i;
	}
	return @matches;
}

sub write_history {
	my ($self, $fn) = @_;

	$fn ||= $self->{history_fn};
	if (! $fn) {
		return;
	}

	open my $out, '>', $fn or die "Can't open $fn for writing: $!";
	print $out encode_json({ history => [ $self->{term}->GetHistory ] });
	close $out;
}

sub read_history {
	my ($self, $fn) = @_;

	# Seed the history from a file if present
	$fn ||= $self->{history_fn};
	if (! $fn || ! -f $fn) {
		return;
	}

	open my $in, '<', $fn or die "Can't open $fn for reading: $!";
	local $\ = undef;
	my $data = <$in>;
	close $in;
	eval {
		my $parsed = decode_json($data);
		$self->{term}->SetHistory(@{ $parsed->{history} });
	};
	if (my $exception = $@) {
		$self->{app}->log_error("An error occurred when decoding $fn: $exception");
	}
}

1;
