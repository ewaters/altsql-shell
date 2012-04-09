package MySQL::ANSIClient::Table;

use strict;
use warnings;
use Data::Dumper;
use Text::ASCIITable;

sub new {
	my $class = shift;

	my %self;

	return bless \%self, $class;
}

sub render {
	my ($self, $data) = @_;

	my $table = Text::ASCIITable->new();

	$table->setCols(map { $_->{name} } @{ $data->{columns} });
	$table->addRow(map { defined $_ ? $_ : 'NULL' } @$_) foreach @{ $data->{rows} };
	
	print $table;
	printf "%d rows in set (%.2f sec)\n", int @{ $data->{rows} }, $data->{timing}{stop} - $data->{timing}{start};
	print "\n";
}

1;
