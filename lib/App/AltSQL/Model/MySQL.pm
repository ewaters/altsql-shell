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

=tiem B<no_auto_rehash>

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
		$self->update_autocomplete_entries($self->database);
	}

	$self->update_db_types();
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

sub show_sql_error {
	my ($self, $input, $char_number, $line_number) = @_;

	my @lines = split /\n/, $input;
	my $line = $lines[ $line_number - 1 ];
	$self->log_error("There was an error parsing the SQL statement on line $line_number:");
	$self->log_error($line);
	$self->log_error(('-' x ($char_number - 1)) . '^');
}

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
