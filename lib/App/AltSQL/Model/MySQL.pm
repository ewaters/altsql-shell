package App::AltSQL::Model::MySQL;

use Moose;
use DBI;
use DBIx::MyParsePP;
use Sys::SigAction qw(set_sig_handler);

with 'App::AltSQL::Role';

has 'sql_parser' => (is => 'ro', default => sub { DBIx::MyParsePP->new() });
has 'dbh'        => (is => 'rw');
has 'current_database' => (is => 'rw');

has 'host' => ( is => 'ro' );
has 'user' => ( is => 'ro' );
has 'password' => ( is => 'ro' );
has 'database' => ( is => 'ro' );
has 'port' => ( is => 'ro' );
has 'no_auto_rehash' => ( is => 'ro' );

no Moose;
__PACKAGE__->meta->make_immutable;

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
		no_auto_rehash => {
			cli  => 'no-auto-rehash|A',
			help => "-A --no-auto-rehash -- Don't scan the information schema for tab autocomplete data",
		},
	);
}

sub db_connect {
	my $self = shift;
	my $dsn = 'DBI:mysql:' . join (';',
		map { "$_=" . $self->$_ }
		grep { defined $self->$_ }
		qw(database host port)
	);
	my $dbh = DBI->connect($dsn, $self->user, $self->password, {
		PrintError => 0,
		mysql_auto_reconnect => 1,
		mysql_enable_utf8 => 1,
	}) or die $DBI::errstr . "\nDSN used: '$dsn'\n";
	$self->dbh($dbh);

	## Update autocomplete entries

	if ($self->database) {
		$self->current_database($self->database);
		$self->update_autocomplete_entries($self->database);
	}

	$self->update_db_types();
}

sub update_autocomplete_entries {
	my ($self, $database) = @_;

	return if $self->no_auto_rehash;
	$self->log_debug("Reading table information for completion of table and column names\nYou can turn off this feature to get a quicker startup with -A\n");

	my %autocomplete;
	my $rows = $self->dbh->selectall_arrayref("select TABLE_NAME, COLUMN_NAME from information_schema.COLUMNS where TABLE_SCHEMA = ?", {}, $database);
	foreach my $row (@$rows) {
		$autocomplete{$row->[0]} = 1; # Table
		$autocomplete{$row->[1]} = 1; # Column
		$autocomplete{$row->[0] . '.' . $row->[1]} = 1; # Table.Column
	}
	$self->app->term->autocomplete_entries(\%autocomplete);
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

	my $view = $self->app->create_view(
		sth => $sth,
		timing => \%timing,
		verb => $verb,
	);
	$view->render(%$render_opts);
}

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


1;
