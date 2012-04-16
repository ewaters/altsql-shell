package MySQL::Client::View;

use Moose;
use Data::Dumper;
use Text::ASCIITable;
use Time::HiRes qw(gettimeofday);
use Params::Validate;
use List::Util qw(sum);

with 'MySQL::Client::Role';
with 'MooseX::Object::Pluggable';

sub args_spec {
	return (
	);
}

sub render_sth {
	my $self = shift;
	my %args = validate(@_, {
		sth  => 1,
		timing => 1,
		verb => 1,
		one_row_per_column => 0,
	});
	my $sth = $args{sth};

	if ($args{verb} eq 'use') {
		$self->log_info('Database changed');
		return;
	}

	if ($sth->{NUM_OF_FIELDS}) {
		my %mysql_meta = (
			map { my $key = $_; $key =~ s/^mysql_//; +($key => $sth->{$_}) }
			qw(mysql_is_blob mysql_is_key mysql_is_num mysql_is_pri_key mysql_is_auto_increment mysql_length mysql_max_length)
		);

		foreach my $i (0..$sth->{NUM_OF_FIELDS} - 1) {
			push @{ $args{columns} }, {
				name      => $sth->{NAME}[$i],
				type      => $sth->{TYPE}[$i],
				precision => $sth->{PRECISION}[$i],
				scale     => $sth->{SCALE}[$i],
				nullable  => $sth->{NULLABLE}[$i] || undef,
				map { $_ => $mysql_meta{$_}[$i] } keys %mysql_meta
			};
		}

		my $t0 = gettimeofday;
		$args{rows} = $sth->fetchall_arrayref;
		$args{timing}{fetchall} = gettimeofday - $t0;

		if (int @{ $args{rows} } == 0) {
			$self->log_info(sprintf "Empty set (%.2f sec)", sum values %{ $args{timing} });
			$self->log_info(''); # empty line
			return;
		}

		if ($args{one_row_per_column}) {
			return $self->render_one_row_per_column(\%args);
		}
		else {
			return $self->render_table(\%args);
		}
	}

	$self->log_info(sprintf 'Query OK, %d row%s affected (%.2f sec)', $sth->rows, ($sth->rows > 1 ? 's' : ''), sum values %{ $args{timing} });
	if ($args{verb} ne 'insert') {
		$self->log_info(sprintf 'Records: %d  Warnings: %d', $sth->rows, $sth->{mysql_warning_count});
	}
	$self->log_info(''); # empty line
}

sub render_table {
	my ($self, $data) = @_;

	my $t0 = gettimeofday;
	my $table = Text::ASCIITable->new({ allowANSI => 1 });

	$table->setCols(map { $self->format_column_cell($_) } @{ $data->{columns} });
	foreach my $row (@{ $data->{rows} }) {
		my @row;
		foreach my $i (0..$#{ $data->{columns} }) {
			push @row, $self->format_cell($row->[$i], $data->{columns}[$i]);
		}
		$table->addRow(@row);
	}
	$data->{timing}{render_table} = gettimeofday - $t0;

	print $table;
	printf "%d rows in set (%.2f sec)\n", int @{ $data->{rows} }, sum values %{ $data->{timing} };
	print "\n";
}

sub render_one_row_per_column {
	my ($self, $data) = @_;

	my $max_length_of_column = 0;
	foreach my $column (@{ $data->{columns} }) {
		my $length = length $column->{name};
		$max_length_of_column = $length if ! $max_length_of_column || $max_length_of_column < $length;
	}

	my $count = 1;
	foreach my $row (@{ $data->{rows} }) {
		print "*************************** $count. row ***************************\n";
		$count++;

		foreach my $i (0..$#{ $data->{columns} }) {
			my $padding_count = $max_length_of_column - length $data->{columns}[$i]{name};
			printf "%s%s: %s\n",
				(' ' x $padding_count),
				$self->format_column_cell($data->{columns}[$i]),
				$self->format_cell($row->[$i], $data->{columns}[$i]);
		}
	}

	printf "%d rows in set (%.2f sec)\n", int @{ $data->{rows} }, sum values %{ $data->{timing} };
	print "\n";
}

sub format_column_cell {
	my ($self, $spec) = @_;

	return $spec->{name};
}

sub format_cell {
	my ($self, $value, $spec) = @_;

	return $value;
}

1;
