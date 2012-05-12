package App::AltSQL::View::Plugin::Color;

use Moose::Role;
use Term::ANSIColor qw(color colored);
no Moose::Role;

my %default_config = (
	header_text => {
		default => 'red',
	},
	cell_text => {
		is_null => 'blue',
		is_primary_key => 'bold',
		is_number => 'yellow',
	},
);

sub format_column_cell {
	my ($self, $spec) = @_;

	return colored $spec->{name}, $self->resolve_namespace_config_value(__PACKAGE__, [ 'header_text', 'default' ], \%default_config);
}

sub format_cell {
	my ($self, $value, $spec) = @_;

	my %colors =
		qw(default is_null is_primary_key is_number);

	my $key = 'default';

	if (! defined $value) {
		$value = 'NULL';
		$key = 'is_null';
	}
	elsif ($spec->{is_pri_key}) {
		$key = 'is_primary_key';
	}
	elsif ($spec->{is_num}) {
		$key = 'is_number';
	}
	else {
		$key = 'default';
	}

	if (my $color = $self->resolve_namespace_config_value(__PACKAGE__, ['cell_text', $key], \%default_config)) {
		return colored $value, $color;
	}
	else {
		return $value;
	}
}

1;
