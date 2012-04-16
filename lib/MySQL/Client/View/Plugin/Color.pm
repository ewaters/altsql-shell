package MySQL::Client::View::Plugin::Color;

use Moose::Role;
use Term::ANSIColor qw(color colored);

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
