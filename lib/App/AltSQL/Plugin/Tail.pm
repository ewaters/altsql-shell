package App::AltSQL::Plugin::Tail;

use Moose::Role;

=head1 TAIL

Given:

 CREATE TABLE log_entries (
   id  int primary key auto_increment,
   ts  datetime not null,
   log varchar(255) not null
 );

The SQL:

 tail ts, log from log_entries every 30;

Will:

 * Find the column 'id', which is the only primary key and is auto_increment
 * Find the current auto_increment value of id as last_seen_max_value
 * Loop:
   - sleep 30 seconds
   - select ts, log from log_entries where id > last_seen_max_value
   - update last_seen_max_value

Other recognized forms:

 tail * from log_entries every 30;
 tail log_entries every 30;

 tail log from log_entries where log like '%ERROR%' every 30;

=cut

around handle_sql_input => sub {
	my ($orig, $self, $input, $render_opts) = @_;

	if ($input !~ m{^tail \s+}x) {
		return $self->$orig($input, $render_opts);
	}

	my ($from, $table, $where, $sleep_seconds) = $input =~
		m{^tail (.+? from|) \s+ (\S+) \s+ (where .+?|) every \s+ (\d+) \s* (?:s|seconds|)$}x;
	if (! defined $table) {
		$self->log_error("Usage: TAIL \$select FROM \$table WHERE \$criteria EVERY \$seconds | TAIL \$table EVERY \$seconds");
		return;
	}

	## Find the primary key, auto_increment column

	my $column_search = $self->dbh->selectall_arrayref(q|
		select
			COLUMN_NAME, IS_NULLABLE, DATA_TYPE, COLUMN_KEY, EXTRA
		from
			information_schema.COLUMNS
		where
			TABLE_SCHEMA = ? and
			TABLE_NAME = ?
	|, { Slice => {} }, $self->current_database, $table);

	my $key_column;
	{
		my @primary_keys = map { $_->{COLUMN_NAME} } grep { $_->{COLUMN_KEY} eq 'PRI' } @$column_search;
		my @autoinc_keys = map { $_->{COLUMN_NAME} } grep { $_->{EXTRA} eq 'auto_increment' } @$column_search;
		if (int @primary_keys == 1 && int @autoinc_keys == 1 && $autoinc_keys[0] eq $primary_keys[0]) {
			$key_column = $primary_keys[0];
		}
		else {
			$self->log_error("Unable to find an auto-incrementing, primary key on the '$table' table");
			return;
		}
	}

	## Find the current max value of this autoincrementing column

	my $last_seen_max_value;
	my $update_last_seen_max_value = sub {
		my $table_status = $self->dbh->selectrow_hashref(q|
			show
				table status
			where
				Name = ?
		|, undef, $table);
		$last_seen_max_value = $table_status->{Auto_increment} - 1;
	};
			
	## Construct tail SQL statement

	$from ||= '* from';
	if ($where) {
		$where .= " and $key_column > ";
	}
	else {
		$where = "where $key_column > ";
	}

	my $tail_sql_fragment = "select $from $table $where";

	## Loop

	my $break = 0;
	$SIG{INT} = sub {
		$break = 1;
	};

	$render_opts->{no_pager} = 1;

	while (1) {
		last if $break;
		$update_last_seen_max_value->();
		sleep $sleep_seconds;
		my $sql = $tail_sql_fragment . $last_seen_max_value;
		$self->log_info( scalar(localtime(time)) . ': ' . $sql);
		$self->$orig($sql, $render_opts);
	}
};

no Moose::Role;

1;
