package App::AltSQL::Term;

use Moose;
use Term::ReadLine::Bender;
use Data::Dumper;
use JSON qw(encode_json decode_json);
use Term::ANSIColor;

with 'App::AltSQL::Role';
with 'MooseX::Object::Pluggable';

has 'term' => (
	is         => 'ro',
	lazy_build => 1,
);
has 'prompt' => (
	is      => 'rw',
	default => 'altsql> ',
);
has 'history_fn'           => ( is => 'ro' );
has 'autocomplete_entries' => ( is => 'rw' );

sub args_spec {
	return (
		history_fn => {
			cli     => 'history=s',
			default => $ENV{HOME} . '/.altsql_history.js',
			help    => '--history FILENAME',
		},
	);
}

sub BUILD {
	my $self = shift;
	$self->log_info("Ctrl-C to reset the line; Ctrl-D to exit");
}

sub setup {
	my $self = shift;
	if (my $custom_prompt = $self->app->config->{prompt}) {
		$self->prompt($custom_prompt);
	}
}

# Very very basic keyword highlighting
my @input_highlighting = (
	{
		color => 'red',
		words => [qw(
			action add after aggregate all alter as asc auto_increment avg avg_row_length
			both by
			cascade change character check checksum column columns comment constraint create cross
			current_date current_time current_timestamp
			data database databases day day_hour day_minute day_second
			default delayed delay_key_write delete desc describe distinct distinctrow drop
			enclosed escape escaped explain
			fields file first flush for foreign from full function
			global grant grants group
			having heap high_priority hosts hour hour_minute hour_second
			identified ignore index infile inner insert insert_id into isam
			join
			key keys kill last_insert_id leading left limit lines load local lock logs long 
			low_priority
			match max_rows middleint min_rows minute minute_second modify month myisam
			natural no
			on optimize option optionally order outer outfile
			pack_keys partial password primary privileges procedure process processlist
			read references reload rename replace restrict returns revoke right row rows
			second select show shutdown soname sql_big_result sql_big_selects sql_big_tables sql_log_off
			sql_log_update sql_low_priority_updates sql_select_limit sql_small_result sql_warnings starting
			status straight_join string
			table tables temporary terminated to trailing type
			unique unlock unsigned update usage use using
			values varbinary variables varying
			where with write
			year_month
			zerofill
		)],
	},
);

# Compile the above into regex
foreach my $syntax_block (@input_highlighting) {
	my $words = join '|', @{ $syntax_block->{words} };
	$syntax_block->{regex} = qr/\b($words)\b/i;
}

sub _build_term {
	my $self = shift;

	my $term = Term::ReadLine::Bender->new("altsql-shell");
	$self->{term} = $term;

	# Require the tab key to be hit twice before showing the list of autocomplete items
	$term->Attribs->{autolist} = 0;

	$term->Attribs->{completion_function} = sub {
		$self->completion_function(@_);
	};

	$term->Attribs->{lines_preprocess_function} = sub {
		my ($lines, $pos) = @_;
		for my $i (0..$#{ $lines }) {
			# Color the main color words (just for the fun)
			$lines->[$i] =~ s{(red|green|yellow|blue|magenta|cyan)}{ colored($1, $1) }egi;
			foreach my $syntax_block (@input_highlighting) {
				$lines->[$i] =~ s/($$syntax_block{regex})/colored($1, $syntax_block->{color})/eg;
			}
		}
	};

	$term->Attribs->{beat} = sub {
		# Check on things in the background here; called every second there is no input from the user
	};

	$term->bindkey('^Z', sub {
		# The Term::ReadLine::Bender uses Term::ReadKey in 'raw' mode which disables all signals
		# If we can find a way to background ourselves at this point, that's the only option that I can see
		$self->log_info("Backgrounding is not currently possible");
	});

	$term->bindkey('^D', sub {
		print "\n";
		$self->app->shutdown();
	});

	$term->bindkey('return', sub { $self->return_key });

	$term->Attribs->{RPS1} = sub { return scalar localtime(time) };

	$self->read_history();

	return $term;
}

sub return_key {
	my $self = shift;

	## The user has pressed the 'enter' key.  If the buffer ends in ';' or '\G', or if they've typed the bare word 'quit' or 'exit', accept the buffer
	my $input = join ' ', @{ $self->term->{lines} };
	if ($input =~ m{(;|\\G|\\c)\s*$} || $input =~ m{^\s*(quit|exit)\s*$} || $input =~ m{^\s*$}) {
		$self->term->accept_line();
	}
	else {
		$self->term->insert_line();
	}
}

sub readline {
	my $self = shift;

	return $self->term->readline($self->render_prompt());
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

my %prompt_substitutions = (
	u => sub { shift->{self}->app->model->user },
	d => sub { shift->{self}->app->model->current_database || '(none)' },
	h => sub { shift->{self}->app->model->host },
	'%' => '%',
);

my %block_prompt_substitutions = (
	c => sub {
		my ($context, $block) = @_;
		return color($block);
	},
	e => sub {
		my ($context, $block) = @_;
		# Make '$self' expected in the current scope so the $block can reference it
		my $self = $context->{self};
		my $return = eval $block;
		if (my $ex = $@) {
			$self->log_error($ex);
			$return = 'err';
		}
		return $return;
	},
	t => sub {
		my ($context, $format) = @_;
		my $now = $context->{date};
		if (! $now) {
			return 'err';
		}
		return $now->strftime($format);
	},
);

sub render_prompt {
	my ($self, $now) = @_;

	if (! defined $self->{_has_datetime}) {
		eval { require DateTime; };
		$self->{_has_datetime} = $@ ? 0 : 1;
	}

	if (! $now && $self->{_has_datetime}) {
		$now = DateTime->now( time_zone => 'local' );
	}

	my %context = (
		self => $self,
		date => $now,
	);

	my $prompt = $self->prompt;
	my $output = '';

	while (length $prompt) {
		my $char = substr $prompt, 0, 1, '';

		# We're looking for a closing brace
		if ($context{requires_block}) {
			if ($char eq '}' && --$context{brace_count} == 0) {
				# Block is complete
				my $sub = $block_prompt_substitutions{ $context{symbol} };
				$output .= $sub->(\%context, delete $context{block});
				delete $context{requires_block};
				delete $context{brace_count};
				next;
			}

			$context{block} .= $char;

			if ($char eq '{') {
				$context{brace_count}++;
			}

			next;
		}

		if ($char eq '%') {
			$context{symbol} = substr $prompt, 0, 1, '';
			if ($block_prompt_substitutions{ $context{symbol} } && substr($prompt, 0, 1) eq '{') {
				substr $prompt, 0, 1, ''; # shift the '{'
				$context{requires_block} = 1;
				$context{block} = '';
				$context{brace_count} = 1;
			}
			else {
				my $sub = $prompt_substitutions{ $context{symbol} };
				if (! $sub) {
					$self->log_error("Unrecognized prompt substitution '$context{symbol}'");
					$output .= $char;
				}
				elsif (ref $sub) {
					$output .= $sub->(\%context);
				}
				else {
					$output .= $sub;
				}
			}
			next;
		}

		$output .= $char;
	}

	return $output;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
