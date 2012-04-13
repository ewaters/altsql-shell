package MySQL::Client;

use Moose;
use Getopt::Long;
use Params::Validate;
use DBI;
use Data::Dumper;
use DBIx::MyParsePP;
use Switch 'Perl6';
use Time::HiRes qw(gettimeofday tv_interval);

our $VERSION = 0.01;

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
		'no-auto-rehash|A' => \$args{no_auto_rehash},
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

has 'term_class' => (is => 'ro', default => 'MySQL::Client::Term');
has 'view_class' => (is => 'ro', default => 'MySQL::Client::View');
has 'term'       => (is => 'ro');
has 'view'       => (is => 'ro');
has 'args'       => (is => 'rw');
has 'sql_parser' => (is => 'ro', default => sub { DBIx::MyParsePP->new() });
has 'dbh'        => (is => 'rw');

sub BUILD {
	my $self = shift;

	$self->db_connect();

	foreach my $subclass (qw(term view)) {
		# Extract out subclass args from args
		my %args = (
			map { my $key = $_; /^_${subclass}_(.+)/; +($1 => delete $self->args->{$key}) }
			grep { /^_${subclass}_/ }
			keys %{ $self->args }
		);

		my $subclass_name = $self->{"${subclass}_class"};

		eval "require $subclass_name";
		die $@ if $@;
		$self->{$subclass} = $subclass_name->new({
			app => $self,
			%args,
		});
	}
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
	}) or die $DBI::errstr . "\nDSN used: '$dsn'\n";

	## Update autocomplete entries

	if ($self->args->{database}) {
		$self->update_autocomplete_entries($self->args->{database});
	}

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

sub update_autocomplete_entries {
	my ($self, $database) = @_;

	return if $self->args->{no_auto_rehash};

	my %autocomplete;
	my $rows = $self->dbh->selectall_arrayref("select TABLE_NAME, COLUMN_NAME from information_schema.COLUMNS where TABLE_SCHEMA = ?", {}, $database);
	foreach my $row (@$rows) {
		$autocomplete{$row->[0]} = 1; # Table
		$autocomplete{$row->[1]} = 1; # Column
		$autocomplete{$row->[0] . '.' . $row->[1]} = 1; # Table.Column
	}
	$self->{autocomplete_entries} = \%autocomplete;

	$self->log_debug("updated autocomplete for $database");
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

	if (my ($database) = $input =~ /^use \s+ (\S+)$/ix) {
		$self->update_autocomplete_entries($database);
	}
}

sub handle_sql_input {
	my ($self, $input, $render_opts) = @_;

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
	$sth->execute();
	if (my $error = $self->dbh->errstr) {
		$self->log_error($error);
		return;
	}

	my %timing = ( prepare_execute => gettimeofday - $t0 );

	$self->view->render_sth(
		sth => $sth,
		timing => \%timing,
		verb => $verb,
		%$render_opts,
	);
}

## Misc utilities

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
