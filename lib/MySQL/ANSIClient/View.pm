package MySQL::ANSIClient::View;

use strict;
use warnings;
use Data::Dumper;
use Text::ASCIITable;
use Term::ANSIColor qw(color colored);
use Params::Validate;

sub new {
	my ($class, $app) = @_;

	my %self = (
		app => $app,
	);

	return bless \%self, $class;
}

sub render_sth {
	my $self = shift;
	my %args = validate(@_, {
		sth  => 1,
		time => 1,
		verb => 1,
		one_row_per_column => 0,
	});
	my $sth = $args{sth};

	if ($args{verb} eq 'use') {
		$self->{app}->log_info('Database changed');
	}
	elsif ($sth->{NUM_OF_FIELDS}) {
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
		$args{rows} = $sth->fetchall_arrayref;
		if ($args{one_row_per_column}) {
			return $self->render_one_row_per_column(\%args);
		}
		else {
			return $self->render_table(\%args);
		}
	}
	else {
		$self->{app}->log_info(sprintf 'Query OK, %d row%s affected (%.2f sec)', $sth->rows, ($sth->rows > 1 ? 's' : ''), $args{time});
		if ($args{verb} ne 'insert') {
			$self->{app}->log_info(sprintf 'Records: %d  Warnings: %d', $sth->rows, $sth->{mysql_warning_count});
		}
		$self->{app}->log_info(''); # empty line
	}
}

sub render_table {
	my ($self, $data) = @_;

	my $table = Text::ASCIITable->new({ allowANSI => 1 });

	$table->setCols(map { $self->format_column_cell($_) } @{ $data->{columns} });
	foreach my $row (@{ $data->{rows} }) {
		my @row;
		foreach my $i (0..$#{ $data->{columns} }) {
			push @row, $self->format_cell($row->[$i], $data->{columns}[$i]);
		}
		$table->addRow(@row);
	}

	print $table;
	printf "%d rows in set (%.2f sec)\n", int @{ $data->{rows} }, $data->{time};
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

	printf "%d rows in set (%.2f sec)\n", int @{ $data->{rows} }, $data->{time};
	print "\n";
}

sub format_column_cell {
	my ($self, $spec) = @_;

	return colored($spec->{name}, "red");
}

sub format_cell {
	my ($self, $value, $spec) = @_;

	if (! defined $value) {
		return colored 'NULL', 'blue';
	}
	elsif ($spec->{is_pri_key}) {
		return colored $value, 'bold';
	}
	elsif ($spec->{is_num}) {
		return colored $value, 'yellow';
	}
	return $value;
}

1;
