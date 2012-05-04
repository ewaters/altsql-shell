package App::AltSQL::Term;

use Moose;
use Term::ReadLine::Zoid;
use Data::Dumper;
use JSON::XS;

with 'App::AltSQL::Role';
with 'MooseX::Object::Pluggable';

has 'term' => (
	is         => 'ro',
	lazy_build => 1,
);
has 'prompt' => (
	is      => 'rw',
	default => 'mysqlc> ',
);
has 'history_fn'           => ( is => 'ro' );
has 'autocomplete_entries' => ( is => 'rw' );

sub args_spec {
	return (
		history_fn => {
			cli     => 'history=s',
			default => $ENV{HOME} . '/.mysqlc_history.js',
			help    => '--history FILENAME',
		},
	);
}

sub BUILD {
	my $self = shift;
	$self->log_info("Ctrl-C to reset the line; Ctrl-D to exit");
}

sub _build_term {
	my $self = shift;

	my $term = Term::ReadLine::Zoid->new("mysql-client");
	$self->{term} = $term;

	$term->Attribs->{completion_function} = sub {
		$self->completion_function(@_);
	};

	$term->bindkey('^D', sub {
		print "\n";
		$self->app->shutdown();
	});

	$term->bindkey('return', sub { $self->return_key });

	$self->read_history();

	return $term;
}

sub return_key {
	my $self = shift;

	## The user has pressed the 'enter' key.  If the buffer ends in ';' or '\G', or if they've typed the bare word 'quit' or 'exit', accept the buffer
	my $input = join ' ', @{ $self->term->{lines} };
	if ($input =~ m{(;|\\G)\s*$} || $input =~ m{^\s*(quit|exit)\s*$}) {
		$self->term->accept_line();
	}
	else {
		$self->term->insert_line();
	}
}

sub readline {
	my $self = shift;

	return $self->term->readline($self->prompt);
}

sub completion_function {
	my ($self, $word, $buffer, $start) = @_;

	#$self->log_debug("\ncompletion_function: '$word', '$buffer', '$start'");

	my $hash = $self->autocomplete_entries;
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

	my @history;
	eval {
		my $parsed = decode_json($data);
		@history = @{ $parsed->{history} };
	};
	if (my $exception = $@) {
		$self->log_error("An error occurred when decoding $fn: $exception");
	}

	$self->term->SetHistory($self->tidy_history(@history));
}

sub tidy_history {
	my ($self, @history) = @_;

	# Filter out exit/quit statements
	@history = grep { ! /^(quit|exit)/ } @history;

	# Limit it to a sane number
	if ($#history > 1_000) {
		splice @history, 0, $#history - 1_000;
	}
	
	return @history;
}

sub get_term_width {
	my $self = shift;
	my ($width, $height) = $self->term->TermSize();
	return $width;
}

sub get_term_height {
	my $self = shift;
	my ($width, $height) = $self->term->TermSize();
	return $height;
}

1;
