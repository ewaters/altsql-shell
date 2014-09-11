package App::AltSQL::Model::MySQL;

=head1 NAME

App::AltSQL::Model::MySQL

=head1 DESCRIPTION

This module is currently the only Model supported by L<App::AltSQL>.

Upon startup, we will read in C<$HOME/.my.cnf> and will read and respect the following configuration variables:

=over 4

=item B<user>

=item B<password>

=item B<host>

=item B<port>

=item B<prompt>

=item B<safe_update>

=item B<select_limit>

=item B<no_auto_rehash>

=back

=cut

use Moose;
use DBI;
use Sys::SigAction qw(set_sig_handler);
use Time::HiRes qw(gettimeofday tv_interval);

extends 'App::AltSQL::Model';

has 'sql_parser' => (is => 'ro', default => sub {
	# Let this be deferred until it's needed, and okay for us to proceed if it's not present
	eval {
		require DBIx::MyParsePP;
	};
	if ($@) {
		return 0; # when we use this we check for definedness as well as boolean
	}
	return DBIx::MyParsePP->new();
});

has [qw(host user password database port)] => ( is => 'ro' );
has [qw(no_auto_rehash select_limit safe_update prompt)] => ( is => 'ro' );

my %prompt_substitutions = (
	S    => ';',
	"'"  => "'",
	'"'  => '"',
	v    => 'TODO-server-version',
	p    => sub { shift->{self}->port },
	'\\' => '\\',
	n    => "\n",
	t    => "\t",
	'_'  => ' ',
	' '  => ' ',
	d    => '%d',
	h    => '%h',
	c    => '%e{ ++( shift->{self}{_statement_counter} ) }',
	u    => '%u',
	U    => '%u@%h',
	D    => '%t{%a, %d %b %H:%M:%S %Y}',
	w    => '%t{%a}',
	y    => '%t{%y}',
	Y    => '%t{%Y}',
	o    => '%t{%m}',
	O    => '%t{%b}',
	R    => '%t{%k}',
	r    => '%t{%I}',
	m    => '%t{%M}',
	s    => '%t{%S}',
	P    => '%t{%p}',
);

sub get_version() {
  return $prompt_substitutions{v};
}

sub args_spec {
	return (
		host => {
			cli         => 'host|h=s',
			help        => '-h HOSTNAME | --host HOSTNAME',
			description => 'The hostname for the database server',
		},
		user => {
			cli         => 'user|u=s',
			help        => '-u USERNAME | --user USERNAME',
			description => 'The username to authenticate as',
		},
		password => {
			help        => '-p | --password=PASSWORD | -pPASSWORD',
			description => 'The password to authenticate with',
		},
		database => {
			cli         => 'database|d=s',
			help        => '-d DATABASE | --database DATABASE',
			description => 'The database to use once connected',
		},
		port => {
			cli         => 'port=i',
			help        => '--port PORT',
			description => 'The port to use for the database server',
		},
		no_auto_rehash => {
			cli         => 'no-auto-rehash|A',
			help        => '-A --no-auto-rehash',
			description => q{Don't scan the information schema for tab autocomplete data},
		},
	);
}

sub setup {
	my $self = shift;
	$self->find_and_read_configs();

	# If the user has configured a custom prompt in .my.cnf and not one in the config, use that in the Term instance
	if ($self->prompt && ! $self->app->config->{prompt}) {
		$self->app->term->prompt( $self->parse_prompt() );
	}
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

	my @valid_keys = qw( user password host port database prompt safe_update select_limit no_auto_rehash ); # keys we'll read
	my @valid_sections = qw( client mysql ); # valid [section] names
	my @boolean_keys = qw( safe_update no_auto_rehash );

	open MYCNF, "<$path";

	# ignore lines in file until we hit a valid [section]
	# then read key=value pairs
	my $in_valid_section = 0;
	while(<MYCNF>) {

		# ignore commented lines:
		/^\s*#/ && next;

		if (/^\s*\[(.*?)\]\s*$/) {                  # we've hit a section
			# verify that we're inside a valid section,
			# and if so, set $in_valid_section
			if ( grep $_ eq $1, @valid_sections ) {
				$in_valid_section = 1;
			} else {
				$in_valid_section = 0;
			}

		} elsif ($in_valid_section) {
			# read a key/value pair
			#/^\s*(.+?)\s*=\s*(.+?)\s*$/;
			#my ($key, $val) = ($1, $2);
			my ($key, $val) = split /\s*=\s*/, $_, 2;

			# value cleanup
			$key =~ s/^\s*(.+?)\s*$/$1/;
			$key || next;
			$key =~ s/-/_/g;

			$val || ( $val = '' );
			$val && $val =~ s/\s*$//;

			# special case for no_auto_rehash, which is 'skip-auto-rehash' in my.cnf
			if ($key eq 'skip_auto_rehash') {
				$key = 'no_auto_rehash';
			}

			# verify that the field is one of the supported ones
			unless ( grep $_ eq $key, @valid_keys ) { next; }

			# if this key is expected to be a boolean, fix the value
			if ( grep $_ eq $key, @boolean_keys ) {
				if ($val eq '0' || $val eq 'false') {
					$val = 0;
				} else {
					# this includes empty values
					$val = 1;
				}
			}

			# override anything that was set on the commandline with the stuff read from the config.
			unless (defined $self->{$key}) { $self->{$key} = $val };
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
		$self->init_autocomplete_entries($self->database);
		$self->update_autocomplete_entries($self->database);
	}

	## Get remote server version
	my $sth = $dbh->prepare('SELECT @@VERSION;');
	$sth->execute();
	my @result = $sth->fetchrow_array();
	$prompt_substitutions{v} = $result[0];
	$self->update_db_types();
}

sub init_autocomplete_entries {
	my ($self, $database) = @_;

	my $cache_key = 'autocomplete_' . $database;
	if (! $self->{_cache}{$cache_key}) {
		$self->log_debug("Initializing with pre-defined keywords...");
        # Keywords as of mysql 5.5
        # http://dev.mysql.com/doc/refman/5.5/en/reserved-words.html
        my %autocomplete = (
            ACCESSIBLE                    => 1,
            ADD                           => 1,
            ALL                           => 1,
            ALTER                         => 1,
            ANALYZE                       => 1,
            AND                           => 1,
            AS                            => 1,
            ASC                           => 1,
            ASENSITIVE                    => 1,
            BEFORE                        => 1,
            BETWEEN                       => 1,
            BIGINT                        => 1,
            BINARY                        => 1,
            BLOB                          => 1,
            BOTH                          => 1,
            BY                            => 1,
            CALL                          => 1,
            CASCADE                       => 1,
            CASE                          => 1,
            CHANGE                        => 1,
            CHAR                          => 1,
            CHARACTER                     => 1,
            CHECK                         => 1,
            COLLATE                       => 1,
            COLUMN                        => 1,
            CONDITION                     => 1,
            CONSTRAINT                    => 1,
            CONTINUE                      => 1,
            CONVERT                       => 1,
            CREATE                        => 1,
            CROSS                         => 1,
            CURRENT_DATE                  => 1,
            CURRENT_TIME                  => 1,
            CURRENT_TIMESTAMP             => 1,
            CURRENT_USER                  => 1,
            CURSOR                        => 1,
            DATABASE                      => 1,
            DATABASES                     => 1,
            DAY_HOUR                      => 1,
            DAY_MICROSECOND               => 1,
            DAY_MINUTE                    => 1,
            DAY_SECOND                    => 1,
            DEC                           => 1,
            DECIMAL                       => 1,
            DECLARE                       => 1,
            DEFAULT                       => 1,
            DELAYED                       => 1,
            DELETE                        => 1,
            DESC                          => 1,
            DESCRIBE                      => 1,
            DETERMINISTIC                 => 1,
            DISTINCT                      => 1,
            DISTINCTROW                   => 1,
            DIV                           => 1,
            DOUBLE                        => 1,
            DROP                          => 1,
            DUAL                          => 1,
            EACH                          => 1,
            ELSE                          => 1,
            ELSEIF                        => 1,
            ENCLOSED                      => 1,
            ESCAPED                       => 1,
            EXISTS                        => 1,
            EXIT                          => 1,
            EXPLAIN                       => 1,
            FALSE                         => 1,
            FETCH                         => 1,
            FLOAT                         => 1,
            FLOAT4                        => 1,
            FLOAT8                        => 1,
            FOR                           => 1,
            FORCE                         => 1,
            FOREIGN                       => 1,
            FROM                          => 1,
            FULLTEXT                      => 1,
            GENERAL                       => 1,
            GRANT                         => 1,
            GROUP                         => 1,
            HAVING                        => 1,
            HIGH_PRIORITY                 => 1,
            HOUR_MICROSECOND              => 1,
            HOUR_MINUTE                   => 1,
            HOUR_SECOND                   => 1,
            IF                            => 1,
            IGNORE                        => 1,
            IGNORE_SERVER_IDS             => 1,
            IN                            => 1,
            INDEX                         => 1,
            INFILE                        => 1,
            INNER                         => 1,
            INOUT                         => 1,
            INSENSITIVE                   => 1,
            INSERT                        => 1,
            INT                           => 1,
            INT1                          => 1,
            INT2                          => 1,
            INT3                          => 1,
            INT4                          => 1,
            INT8                          => 1,
            INTEGER                       => 1,
            INTERVAL                      => 1,
            INTO                          => 1,
            IS                            => 1,
            ITERATE                       => 1,
            JOIN                          => 1,
            KEY                           => 1,
            KEYS                          => 1,
            KILL                          => 1,
            LEADING                       => 1,
            LEAVE                         => 1,
            LEFT                          => 1,
            LIKE                          => 1,
            LIMIT                         => 1,
            LINEAR                        => 1,
            LINES                         => 1,
            LOAD                          => 1,
            LOCALTIME                     => 1,
            LOCALTIMESTAMP                => 1,
            LOCK                          => 1,
            LONG                          => 1,
            LONGBLOB                      => 1,
            LONGTEXT                      => 1,
            LOOP                          => 1,
            LOW_PRIORITY                  => 1,
            MASTER_HEARTBEAT_PERIOD       => 1,
            MASTER_SSL_VERIFY_SERVER_CERT => 1,
            MATCH                         => 1,
            MAXVALUE                      => 1,
            MEDIUMBLOB                    => 1,
            MEDIUMINT                     => 1,
            MEDIUMTEXT                    => 1,
            MIDDLEINT                     => 1,
            MINUTE_MICROSECOND            => 1,
            MINUTE_SECOND                 => 1,
            MOD                           => 1,
            MODIFIES                      => 1,
            NATURAL                       => 1,
            NOT                           => 1,
            NO_WRITE_TO_BINLOG            => 1,
            NULL                          => 1,
            NUMERIC                       => 1,
            ON                            => 1,
            OPTIMIZE                      => 1,
            OPTION                        => 1,
            OPTIONALLY                    => 1,
            OR                            => 1,
            ORDER                         => 1,
            OUT                           => 1,
            OUTER                         => 1,
            OUTFILE                       => 1,
            PRECISION                     => 1,
            PRIMARY                       => 1,
            PROCEDURE                     => 1,
            PURGE                         => 1,
            RANGE                         => 1,
            READ                          => 1,
            READS                         => 1,
            READ_WRITE                    => 1,
            REAL                          => 1,
            REFERENCES                    => 1,
            REGEXP                        => 1,
            RELEASE                       => 1,
            RENAME                        => 1,
            REPEAT                        => 1,
            REPLACE                       => 1,
            REQUIRE                       => 1,
            RESIGNAL                      => 1,
            RESTRICT                      => 1,
            RETURN                        => 1,
            REVOKE                        => 1,
            RIGHT                         => 1,
            RLIKE                         => 1,
            SCHEMA                        => 1,
            SCHEMAS                       => 1,
            SECOND_MICROSECOND            => 1,
            SELECT                        => 1,
            SENSITIVE                     => 1,
            SEPARATOR                     => 1,
            SET                           => 1,
            SHOW                          => 1,
            SIGNAL                        => 1,
            SLOW                          => 1,
            SMALLINT                      => 1,
            SPATIAL                       => 1,
            SPECIFIC                      => 1,
            SQL                           => 1,
            SQL_BIG_RESULT                => 1,
            SQL_CALC_FOUND_ROWS           => 1,
            SQLEXCEPTION                  => 1,
            SQL_SMALL_RESULT              => 1,
            SQLSTATE                      => 1,
            SQLWARNING                    => 1,
            SSL                           => 1,
            STARTING                      => 1,
            STRAIGHT_JOIN                 => 1,
            TABLE                         => 1,
            TERMINATED                    => 1,
            THEN                          => 1,
            TINYBLOB                      => 1,
            TINYINT                       => 1,
            TINYTEXT                      => 1,
            TO                            => 1,
            TRAILING                      => 1,
            TRIGGER                       => 1,
            TRUE                          => 1,
            UNDO                          => 1,
            UNION                         => 1,
            UNIQUE                        => 1,
            UNLOCK                        => 1,
            UNSIGNED                      => 1,
            UPDATE                        => 1,
            USAGE                         => 1,
            USE                           => 1,
            USING                         => 1,
            UTC_DATE                      => 1,
            UTC_TIME                      => 1,
            UTC_TIMESTAMP                 => 1,
            VALUES                        => 1,
            VARBINARY                     => 1,
            VARCHAR                       => 1,
            VARCHARACTER                  => 1,
            VARYING                       => 1,
            WHEN                          => 1,
            WHERE                         => 1,
            WHILE                         => 1,
            WITH                          => 1,
            WRITE                         => 1,
            XOR                           => 1,
            YEAR_MONTH                    => 1,
            ZEROFILL                      => 1,
            # Show queries as of mysql 5.5
            # http://dev.mysql.com/doc/refman/5.5/en/show.html
            'SHOW'          => 1,
            'AUTHORS'          => 1,
            'BINARY LOGS'      => 1,
            'BINLOG EVENTS'    => 1,
            'CHARACTER SET'    => 1,
            'COLLATION'        => 1,
            'COLUMNS'          => 1,
            'CONTRIBUTORS'     => 1,
            'CREATE DATABASE'  => 1,
            'CREATE EVENT'     => 1,
            'CREATE FUNCTION'  => 1,
            'CREATE PROCEDURE' => 1,
            'CREATE TABLE'     => 1,
            'CREATE TRIGGER'   => 1,
            'CREATE VIEW'      => 1,
            'DATABASES'        => 1,
            'ENGINE'           => 1,
            'ENGINES'          => 1,
            'ERRORS'           => 1,
            'EVENTS'           => 1,
            'FUNCTION CODE'    => 1,
            'FUNCTION STATUS'  => 1,
            'GRANTS'           => 1,
            'INDEX'            => 1,
            'MASTER STATUS'    => 1,
            'OPEN TABLES'      => 1,
            'PLUGINS'          => 1,
            'PRIVILEGES'       => 1,
            'PROCEDURE CODE'   => 1,
            'PROCEDURE STATUS' => 1,
            'PROCESSLIST'      => 1,
            'PROFILE'          => 1,
            'PROFILES'         => 1,
            'RELAYLOG EVENTS'  => 1,
            'SLAVE HOSTS'      => 1,
            'SLAVE STATUS'     => 1,
            'STATUS'           => 1,
            'TABLE STATUS'     => 1,
            'TABLES'           => 1,
            'TRIGGERS'         => 1,
            'VARIABLES'        => 1,
            'WARNINGS'         => 1,
        );
		$self->{_cache}{$cache_key} =  \%autocomplete;
	}
	$self->app->term->autocomplete_entries( $self->{_cache}{$cache_key} );
}
sub update_autocomplete_entries {
	my ($self, $database) = @_;

	return if $self->no_auto_rehash;
	my $cache_key = 'autocomplete_' . $database;
	if (! $self->{_cache}{$cache_key}) {
		$self->log_debug("Reading table information for completion of table and column names\nYou can turn off this feature to get a quicker startup with -A\n");

		my %autocomplete;
		my $rows = $self->dbh->selectall_arrayref("select TABLE_NAME, COLUMN_NAME from information_schema.COLUMNS where TABLE_SCHEMA = ?", {}, $database);
		foreach my $row (@$rows) {
			$autocomplete{$row->[0]} = 1; # Table
			$autocomplete{$row->[1]} = 1; # Column
			$autocomplete{$row->[0] . '.' . $row->[1]} = 1; # Table.Column
		}
		$self->{_cache}{$cache_key} = \%autocomplete;
	}
	$self->app->term->autocomplete_entries( $self->{_cache}{$cache_key} );
}

sub handle_sql_input {
	my ($self, $input, $render_opts) = @_;

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

	# Track which database we're in for autocomplete
	if (my ($database) = $input =~ /^use \s+ (\S+)$/ix) {
		$self->current_database($database);
		$self->update_autocomplete_entries($database);
	}

	my %timing = ( prepare_execute => gettimeofday - $t0 );

	my $view = $self->app->create_view(
		sth => $sth,
		timing => \%timing,
		verb => $verb,
		column_meta => {
			map { my $key = $_; $key =~ s/^mysql_//; +($key => $sth->{$_}) }
			qw(mysql_is_blob mysql_is_key mysql_is_num mysql_is_pri_key mysql_is_auto_increment mysql_length mysql_max_length)
		},
	);
	$view->render(%$render_opts);

	return $view;
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


=cut

Take a .my.cnf prompt format and convert it into Term escape options

Reference:
http://www.thegeekstuff.com/2010/02/mysql_ps1-6-examples-to-make-your-mysql-prompt-like-angelina-jolie/

=cut

sub parse_prompt {
	my $self = shift;

	my $parsed_prompt = $self->prompt;
	$parsed_prompt =~ s{\\\\(.)}{
		my $substitute = $prompt_substitutions{$1};
		if (! $substitute) {
			"$1";
		}
		elsif (ref $substitute) {
			$substitute->($self);
		}
		else {
			$substitute;
		}
	}exg;

	return $parsed_prompt;
}

no Moose;
__PACKAGE__->meta->make_immutable;

=head1 COPYRIGHT

Copyright (c) 2012 Eric Waters and Shutterstock Images (http://shutterstock.com).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
