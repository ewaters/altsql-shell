package MySQL::ANSIClient::Table;

use strict;
use warnings;
use Data::Dumper;
use Text::ASCIITable;
use Term::ANSIColor qw(color colored);

sub new {
	my ($class, $app) = @_;

	my %self = (
		app => $app,
	);

	return bless \%self, $class;
}

sub render {
	my ($self, $data, $opts) = @_;

	my $table = Text::ASCIITable->new({ allowANSI => 1 });

	if ($opts->{one_row_per_table}) {
		$table->setCols('column', 'value');
		foreach my $row (@{ $data->{rows} }) {
			$table->addRowLine();
			foreach my $i (0..$#{ $data->{columns} }) {
				$table->addRow(
					$self->format_column_cell($data->{columns}[$i]),
					$self->format_cell($row->[$i], $data->{columns}[$i], $opts)
				);
			}
			$table->alignCol({ column => 'right', value => 'left' });
		}
	}
	else {
		$table->setCols(map { $self->format_column_cell($_, $opts) } @{ $data->{columns} });
		foreach my $row (@{ $data->{rows} }) {
			my @row;
			foreach my $i (0..$#{ $data->{columns} }) {
				push @row, $self->format_cell($row->[$i], $data->{columns}[$i], $opts);
			}
			$table->addRow(@row);
		}
	}

	print $table;
	printf "%d rows in set (%.2f sec)\n", int @{ $data->{rows} }, $data->{timing}{stop} - $data->{timing}{start};
	print "\n";
}

sub format_column_cell {
	my ($self, $spec, $opts) = @_;

	return colored($spec->{name}, "red");
}

sub format_cell {
	my ($self, $value, $spec, $opts) = @_;

	my $type = $self->{app}->db_type_info( $spec->{type} );

	if (! defined $value) {
		return colored 'NULL', 'blue';
	}
	if ($type->{TYPE_NAME} ne 'unknown') {
		if ($type->{mysql_is_num}) {
			return colored $value, 'yellow';
		}
		elsif ($type->{TYPE_NAME} eq 'date') {
			return colored $value, 'yellow bold';
		}
	}
	return $value;
}

1;
