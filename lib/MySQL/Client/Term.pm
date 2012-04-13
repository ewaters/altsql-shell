package MySQL::Client::Term;

use Moose;
use Term::ReadLine::Zoid;
use Data::Dumper;
use JSON::XS;

with 'MySQL::Client::Role';

has 'term' => (
	is         => 'ro',
	lazy_build => 1,
);
has 'prompt' => (
	is      => 'rw',
	default => 'myqslc> ',
);
has 'history_fn' => (
	is => 'ro',
);

sub BUILD {
	my $self = shift;
	$self->log_info("Ctrl-C to reset the line; Ctrl-D to exit");
}

sub _build_term {
	my $self = shift;

	my $term = Term::ReadLine::Zoid->new("mysql-color");
	$self->{term} = $term;

	$term->Attribs->{completion_function} = sub {
		$self->completion_function(@_);
	};

	$term->bindkey('^D', sub {
		print "\n";
		$self->app->shutdown();
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

	return $term;
}

sub readline {
	my $self = shift;

	return $self->term->readline($self->prompt);
}

sub completion_function {
	my ($self, $word, $buffer, $start) = @_;

	#$self->log_debug("\ncompletion_function: '$word', '$buffer', '$start'");

	my $hash = $self->app->{autocomplete_entries};
	return () unless $hash;

	my @matches;
	foreach my $key (sort keys %$hash) {
		push @matches, $key if $key =~ m/^$word/i;
	}
	return @matches;
}

sub write_history {
	my ($self, $fn) = @_;

	$fn ||= $self->history_fn;
	if (! $fn) {
		return;
	}

	open my $out, '>', $fn or die "Can't open $fn for writing: $!";
	print $out encode_json({ history => [ $self->term->GetHistory ] });
	close $out;
}

sub read_history {
	my ($self, $fn) = @_;

	# Seed the history from a file if present
	$fn ||= $self->history_fn;
	if (! $fn || ! -f $fn) {
		return;
	}

	open my $in, '<', $fn or die "Can't open $fn for reading: $!";
	local $\ = undef;
	my $data = <$in>;
	close $in;
	eval {
		my $parsed = decode_json($data);
		$self->term->SetHistory(@{ $parsed->{history} });
	};
	if (my $exception = $@) {
		$self->log_error("An error occurred when decoding $fn: $exception");
	}
}

1;
