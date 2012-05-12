package App::AltSQL;

use Moose;
use Getopt::Long qw(GetOptionsFromArray);
use Params::Validate;
use DBI;
use Data::Dumper;
use DBIx::MyParsePP;
use Switch 'Perl6';
use Time::HiRes qw(gettimeofday tv_interval);
use Sys::SigAction qw(set_sig_handler);

our $VERSION = 0.01;
our $| = 1;

# Don't emit 'Wide character in output' warnings
binmode STDOUT, ':utf8';

with 'MooseX::Object::Pluggable';

my %_default_classes = (
	term => 'App::AltSQL::Term',
	view => 'App::AltSQL::View',
);
has 'term'       => (is => 'ro');
has 'view'       => (is => 'ro');
has 'args'       => (is => 'rw');
has 'sql_parser' => (is => 'ro', default => sub { DBIx::MyParsePP->new() });
has 'dbh'        => (is => 'rw');
has 'current_database' => (is => 'rw');

no Moose;
__PACKAGE__->meta->make_immutable;

## Configure

sub args_spec {
	return (
		host => {
			cli  => 'host|h=s',
			help => '-h HOSTNAME | --host HOSTNAME',
		},
		user => {
			cli  => 'user|u=s',
			help => '-u USERNAME | --user USERNAME',
		},
		
		password => {
			help => '-p | --password=PASSWORD | -pPASSWORD',
		},
		database => {
			cli  => 'database|d=s',
			help => '-d DATABASE | --database DATABASE',
		},
		port => {
			cli  => 'port=i',
			help => '--port PORT',
		},
		help => {
			cli  => 'help|?',
		},
		no_auto_rehash => {
			cli  => 'no-auto-rehash|A',
			help => "-A --no-auto-rehash -- Don't scan the information schema for tab autocomplete data",
		},
	);
}

sub BUILD {
	my $self = shift;

	foreach my $subclass (qw(term view)) {
		# Extract out subclass args from args
		my %args = (
			map { my $key = $_; /^_${subclass}_(.+)/; +($1 => delete $self->args->{$key}) }
			grep { /^_${subclass}_/ }
			keys %{ $self->args }
		);

		my $subclass_name = $self->args->{"${subclass}_class"};

		eval "require $subclass_name";
		die $@ if $@;

		if ($subclass eq 'term') {
			$self->{$subclass} = $subclass_name->new({
				app => $self,
				%args,
			});
		}
		else {
			$self->args->{view_args} = \%args;
		}
	}

	$self->db_connect();
}

sub db_connect {
	my $self = shift;
	my $dsn = 'DBI:mysql:' . join (';',
		map { "$_=$self->{args}{$_}" }
		grep { defined $self->{args}{$_} }
		qw(database host port)
	);
	$self->{dbh} = DBI->connect($dsn, $self->args->{user}, $self->args->{password}, {
		PrintError => 0,
		mysql_auto_reconnect => 1,
		mysql_enable_utf8 => 1,
	}) or die $DBI::errstr . "\nDSN used: '$dsn'\n";

	## Update autocomplete entries

	if ($self->args->{database}) {
		$self->current_database($self->args->{database});
		$self->update_autocomplete_entries($self->args->{database});
	}

	$self->update_db_types();
}

sub update_autocomplete_entries {
	my ($self, $database) = @_;

	return if $self->args->{no_auto_rehash};
	$self->log_debug("Reading table information for completion of table and column names\nYou can turn off this feature to get a quicker startup with -A\n");

	my %autocomplete;
	my $rows = $self->dbh->selectall_arrayref("select TABLE_NAME, COLUMN_NAME from information_schema.COLUMNS where TABLE_SCHEMA = ?", {}, $database);
	foreach my $row (@$rows) {
		$autocomplete{$row->[0]} = 1; # Table
		$autocomplete{$row->[1]} = 1; # Column
		$autocomplete{$row->[0] . '.' . $row->[1]} = 1; # Table.Column
	}
	$self->term->autocomplete_entries(\%autocomplete);
}

sub parse_cli_args {
	my ($class, $argv, %args) = @_;
	my @argv = defined $argv ? @$argv : ();

	# Read in the args_spec() from each subclass we'll be using
	my %opts_spec;
	$args{term_class} ||= $_default_classes{term};
	$args{view_class} ||= $_default_classes{view};
	foreach my $args_class ('main', 'view', 'term') {
		if ($args_class eq 'main') {
			my %args_spec = $class->args_spec();
			foreach my $arg (keys %args_spec) {
				next unless $args_spec{$arg}{cli};
				$opts_spec{ $args_spec{$arg}{cli} } = \$args{$arg};
			}
		}
		else {
			my $args_classname = $args{"${args_class}_class"};
			eval "require $args_classname";
			die $@ if $@;
			my %args_spec = $args_classname->args_spec();
			foreach my $key (keys %args_spec) {
				next unless $args_spec{$key}{cli};
				$opts_spec{ $args_spec{$key}{cli} } = \$args{"_${args_class}_$key"};
				if (my $default = $args_spec{$key}{default}) {
					$args{"_${args_class}_$key"} = $default;
				}
			}
		}
	}

	# Password is a special case
	foreach my $i (0..$#argv) {
		my $arg = $argv[$i];
		next unless $arg =~ m{^(?:-p|--password=)(.*)$};
		splice @argv, $i, 1;
		if (length $1) {
			$args{password} = $1;
			# Remove the password from the program name so people can't see it in process listings
			$0 = join ' ', $0, @argv;
		}
		else {
			# Prompt the user for the password
			require Term::ReadKey;
			Term::ReadKey::ReadMode('noecho');
			print "Enter password: ";
			$args{password} = Term::ReadKey::ReadLine(0);
			Term::ReadKey::ReadMode('normal');
			print "\n";
			chomp $args{password};
		}
		last; # I've found what I was looking for
	}

	GetOptionsFromArray(\@argv, %opts_spec);

	# Database is a special case; if left over arguments, that's the database name
	if (@argv && int @argv == 1) {
		$args{database} = $argv[0];
	}

	return \%args;
}

sub new_from_cli {
	my $class = shift;
	my $args = $class->parse_cli_args(\@ARGV);
	if ($args->{help}) {
		print "TODO from spec!\n";
		exit;
	}
	return $class->new(args => $args);
}

## Main

sub run {
	my $self = shift;

	$self->log_info("Starting ".__PACKAGE__);

	my $input;
	while (defined ($input = $self->term->readline())) {
		$self->handle_term_input($input);
	}
}

sub shutdown {
	my $self = shift;

	$self->term->write_history();

	exit;
}

## Input handlers

sub handle_term_input {
	my ($self, $input) = @_;

	# Next if Ctrl-C or if user typed nothing
	if (! length $input) {
		return;
	}

	$input =~ s/\s*$//; # no trailing spaces
	$input =~ s/;*$//;  # no trailing semicolon

	# Extract out \G
	my %render_opts;
	if ($input =~ s/\\G$//) {
		$render_opts{one_row_per_column} = 1;
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
		return;
	}

	$self->handle_sql_input($input, \%render_opts);
}

sub handle_sql_input {
	my ($self, $input, $render_opts) = @_;

	# Track which database we're in for autocomplete
	if (my ($database) = $input =~ /^use \s+ (\S+)$/ix) {
		$self->current_database($database);
		$self->update_autocomplete_entries($database);
	}

	# Attempt to parse the input with a SQL parser
	my $parsed = $self->sql_parser->parse($input);
	if (! defined $parsed->root) {
		$self->log_error(sprintf "Error at pos %d, line %s", $parsed->pos, $parsed->line);
		return;
	}

	# Figure out the verb
	my $statement = $parsed->root->extract('statement');
	if (! $statement) {
		$self->log_error("Not sure what to do with this; no 'statement' in the parse tree");
		return;
	}
	my $verb = $statement->children->[0];

	# Run the SQL
	
	my $t0 = gettimeofday;

	my $sth = $self->dbh->prepare($input);

	# Execute the statement, allowing Ctrl-C to interrupt the call
	eval {
		eval {
			my $h = set_sig_handler('INT', sub {
				my $thread_id = $self->dbh->{mysql_thread_id};
				$self->dbh->clone->do("KILL QUERY $thread_id");
				die "Query aborted by Ctrl+C\n";
			});
			$sth->execute();
		};
		die "$@" if $@;
	};

	if (my $error = $self->dbh->errstr || $@) {
		$self->log_error($error);
		return;
	}

	my %timing = ( prepare_execute => gettimeofday - $t0 );

	my $view = $self->args->{view_class}->new(
		app => $self,
		sth => $sth,
		timing => \%timing,
		verb => $verb,
		%{ $self->args->{view_args} },
	);

	# FIXME: Make this configurable somehow
	$view->load_plugin($_) foreach qw(Color UnicodeBox);

	$view->render(%$render_opts);
}

## Misc utilities

sub update_db_types {
	my $self = shift;

	## Collect type info from the handle

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
