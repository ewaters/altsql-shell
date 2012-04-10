package MySQL::ANSIClient;

use strict;
use warnings;
use Getopt::Long;
use Params::Validate;
use DBI;
use Data::Dumper;
use DBIx::MyParsePP;
use Switch 'Perl6';
use Time::HiRes qw(gettimeofday tv_interval);

## Configure

sub help_text {
	return <<EOF;

  -h --host HOSTNAME
  -u --user USERNAME
  -p --pass PASSWORD
  -P --port PORT
  -d --database DATABASE
  -? --help
EOF
}

sub capture_command_line_args {
	my $class = shift;
	my %args;
	GetOptions(
		'host|h=s' => \$args{host},
		'user|u=s' => \$args{user},
		'pass|p=i' => \$args{password},
		'database|d=s' => \$args{database},
		'port|P=s' => \$args{port},
		'help|?'   => \$args{help},
		'history=s' => \$args{_term_history_fn},
	);
	if (@ARGV && int @ARGV == 1) {
		$args{database} = $ARGV[0];
	}
	$args{_term_history_fn} ||= $ENV{HOME} . '/.mysqlc_history.js';
	if ($args{help}) {
		print $class->help_text();
		exit;
	}
	return %args;
}

sub new {
	my $class = shift;
	my %self = validate(@_, {
		term_class  => { default => 'MySQL::ANSIClient::Term' },
		table_class => { default => 'MySQL::ANSIClient::Table' },
		args => 1,
	});
	my $self = bless \%self, $class;

	$self->db_connect();

	## Create a term

	# Extract out term args from args
	$self->{term_args} = {
		map { my $key = $_; /^_term_(.+)/; +($1 => delete $self->{args}{$key}) }
		grep { /^_term_/ }
		keys %{ $self->{args} }
	};

	my $term_class = $self->{term_class};
	eval "require $term_class";
	die $@ if $@;
	$self->{term} = $term_class->new(
		app => $self,
		%{ $self->{term_args} },
	);

	## Create a table render

	my $table_class = $self->{table_class};
	eval "require $table_class";
	die $@ if $@;
	$self->{table} = $table_class->new($self);

	## Create other reusable objects

	$self->{sql_parser} = DBIx::MyParsePP->new();

	return $self;
}

sub db_connect {
	my $self = shift;
	my $dsn = 'DBI:mysql:' . join (';',
		map { "$_=$self->{args}{$_}" }
		grep { defined $self->{args}{$_} }
		qw(database host port)
	);
	$self->{dbh} = DBI->connect($dsn, $self->{args}{user}, $self->{args}{password}, {
		PrintError => 0,
	}) or die $DBI::errstr . "\nDSN used: '$dsn'\n";

	my %types;
	my $type_info_all = $self->{dbh}->type_info_all();
	my %key_map = %{ shift @$type_info_all };

	$types{unknown} = { map { $_ => 'unknown' } keys %key_map };

	foreach my $i (0..$#{ $type_info_all }) {
		my %type;
		while (my ($key, $index) = each %key_map) {
			$type{$key} = $type_info_all->[$i][$index];
		}
		$types{$i} = \%type;
	}

	$self->{db_types} = \%types;
}

sub new_from_cli {
	my $class = shift;

	my %args = $class->capture_command_line_args;
	if ($args{help}) {
		$class->log_info($class->help_text);
		exit;
	}

	return $class->new(args => \%args);
}

## Main

sub run {
	my $self = shift;

	$self->log_info("Starting ".__PACKAGE__);

	my $input;
	while (defined ($input = $self->{term}->readline())) {
		# Next if Ctrl-C or if user typed nothing
		if (! length $input) {
			next;
		}

		$input =~ s/\s*$//; # no trailing spaces
		$input =~ s/;*$//;  # no trailing semicolon

		# Extract out \G
		my %render_opts;
		if ($input =~ s/\\G$//) {
			$render_opts{one_row_per_table} = 1;
		}

		# Allow the user to pass non-SQL control verbs
		if ($input =~ m/^\s*(quit|exit)\s*$/) {
			$self->shutdown();
		}

		# Allow the user to execute perl code via '% print Dumper(...);'
		if (my ($perl_code) = $input =~ m/^% (.+)$/) {
			eval $perl_code;
			if ($@) {
				$self->log_error($@);
			}
			next;
		}

		$self->handle_sql_input($input, \%render_opts);
	}
}

sub shutdown {
	my $self = shift;

	$self->{term}->write_history();

	exit;
}

sub handle_sql_input {
	my ($self, $input, $render_opts) = @_;

	# Attempt to parse the input with a SQL parser
	my $parsed = $self->{sql_parser}->parse($input);
	if (! defined $parsed->root) {
		$self->log_error(sprintf "Error at pos %d, line %s", $parsed->pos, $parsed->line);
		return;
	}

	# Based on the context of what type of action is being performed, print a table or print just a success/failure
	my $statement = $parsed->root->extract('statement');
	if (! $statement) {
		$self->log_error("Not sure what to do with this; no 'statement' in the parse tree");
		return;
	}

	my $sql = $parsed->toString;

	my $output_type = 'query';
	my $verb = $statement->children->[0];
	given ($verb) {
		when [qw( select describe explain show )] { $output_type = 'table' }
		when [qw( use create alter update insert delete )]      { $output_type = 'query' }
		default {
			$self->log_info("I don't know how to handle '$verb'; assume non-table output");
		}
	}
	
	my %data;
	$data{timing}{start} = gettimeofday;

	my $sth = $self->{dbh}->prepare($sql);
	$sth->execute();
	if (my $error = $self->{dbh}->errstr) {
		$self->log_error($error);
		return;
	}

	$data{timing}{stop} = gettimeofday;

	if ($output_type eq 'table') {
		foreach my $i (0..$sth->{NUM_OF_FIELDS} - 1) {
			push @{ $data{columns} }, {
				name      => $sth->{NAME}[$i],
				type      => $sth->{TYPE}[$i],
				precision => $sth->{PRECISION}[$i],
				scale     => $sth->{SCALE}[$i],
				nullable  => $sth->{NULLABLE}[$i] || undef,
			};
		}
		$data{rows} = $sth->fetchall_arrayref;
		$self->{table}->render(\%data, $render_opts);
	}
	elsif ($verb eq 'use') {
		$self->log_info('Database changed');
	}
	else {
		$self->log_info(sprintf 'Query OK, %d row%s affected (%.2f sec)', $sth->rows, ($sth->rows > 1 ? 's' : ''), $data{timing}{stop} - $data{timing}{start});
		if ($verb ne 'insert') {
			$self->log_info(sprintf 'Records: %d  Warnings: %d', $sth->rows, $sth->{mysql_warning_count});
		}
		$self->log_info(''); # empty line
	}
}

sub db_type_info {
	my ($self, $type) = @_;

	my $info = $self->{db_types}{$type};
	if (! $info) {
		#$self->log_error("No such type info for $type");
		return $self->{db_types}{unknown};
	}
	return $info;
}

## Output display

sub log_info {
	my ($self, $message) = @_;
	print $message . "\n";
}

sub log_debug {
	return log_info(@_);
}

sub log_error {
	return log_info(@_);
}

1;
