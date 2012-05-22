package App::AltSQL::Model::MySQL;

use Moose;
use DBI;
use Sys::SigAction qw(set_sig_handler);
use Time::HiRes qw(gettimeofday tv_interval);

extends 'App::AltSQL::Model';

has 'sql_parser' => (is => 'ro', default => sub {
	# Let this be deferred until it's needed, and okay for us to proceed if it's not present
	eval "require DBIx::MyParsePP;";
	if ($@) {
		return 0; # when we use this we check for definedness as well as boolean
	}
	return DBIx::MyParsePP->new();
});
has 'dbh'        => (is => 'rw');
has 'current_database' => (is => 'rw');

has [qw(host user password database port)] => ( is => 'ro' );
has [qw(no_auto_rehash select_limit safe_update prompt)] => ( is => 'ro' );

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

sub BUILD {
  my $self = shift;
  
  # locate and read the my.conf
  $self->find_and_read_configs();
}

sub find_and_read_configs {
  my $self = shift;
  my @config_paths = ( 
    "$ENV{HOME}/.my.cnf",
  );
  
  foreach my $path (@config_paths) {
    (-e $path) or next;
    $self->read_my_dot_cnf($path);
  }
}

sub read_my_dot_cnf {
  my $self = shift;
  my $path = shift;
  
  my @valid_keys = qw( user password host port database );
  
  open MYCNF, "<$path" or return;
  
  # ignore lines in file until we hit a [client] section
  # then read key=value pairs
  my $in_client = 0;
  while(<MYCNF>) {
    # ignore commented lines:
    /^\s*#/ && next;
    
    if (/^\s*\[(.*?)\]\s*$/) {                  # we've hit a section
      if ("$1" eq 'client')   { $in_client++; } # we've hit a client section, increment it
      if ($in_client > 1)     { last; }         # end because we're done; we already read the client section
    } elsif ($in_client == 1) {
      # read a key/value pair
      /^\s*(.+?)\s*=\s*(.+?)\s*$/;
      my ($key, $val) = ($1, $2);
      
      # verify that the field is one of the supported ones
      unless ( grep $_ eq $key, @valid_keys ) { next; }
            
      # override anything that was set on the commandline with the stuff read from the config.
      unless ($self->{$key}) { $self->{$key} = $val };
    }
  }
  
  close MYCNF;
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

	# Figure out the verb of the SQL by either using regex or a parser.  If we
	# use the parser, we get error checking here instead of the server.
	my $verb;
	if (defined $self->sql_parser && $self->sql_parser) {
		# Attempt to parse the input with a SQL parser
		my $parsed = $self->sql_parser->parse($input);
		if (! defined $parsed->root) {
			$self->show_sql_error($input, $parsed->pos, $parsed->line);
			return;
		}

		# Figure out the verb
		my $statement = $parsed->root->extract('statement');
		if (! $statement) {
			$self->log_error("Not sure what to do with this; no 'statement' in the parse tree");
			return;
		}
		$verb = $statement->children->[0];
	}
	else {
		($verb, undef) = split /\s+/, $input, 2;
	}

	# Run the SQL
	
	my $t0 = gettimeofday;

	my $sth = $self->execute_sql($input);
	return unless $sth; # error may have been reached (and reported)

	my %timing = ( prepare_execute => gettimeofday - $t0 );

	my $view = $self->app->create_view(
		sth => $sth,
		timing => \%timing,
		verb => $verb,
	);
	$view->render(%$render_opts);
}

sub execute_sql {
	my ($self, $input) = @_;

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

	return $sth;
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

sub show_sql_error {
	my ($self, $input, $char_number, $line_number) = @_;

	my @lines = split /\n/, $input;
	my $line = $lines[ $line_number - 1 ];
	$self->log_error("There was an error parsing the SQL statement on line $line_number:");
	$self->log_error($line);
	$self->log_error(('-' x ($char_number - 1)) . '^');
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
