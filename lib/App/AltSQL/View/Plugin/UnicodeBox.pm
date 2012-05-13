package App::AltSQL::View::Plugin::UnicodeBox;

use Moose::Role;
use Text::UnicodeBox::Table;

my %default_config = (
	style => 'heavy_header',
	split_lines => 1,
);

sub _render_table_data {
	my ($self, $data) = @_;

	my $table = Text::UnicodeBox::Table->new(
		split_lines => $self->resolve_namespace_config_value(__PACKAGE__, 'split_lines', \%default_config),
		style       => $self->resolve_namespace_config_value(__PACKAGE__, 'style', \%default_config),
		($self->resolve_namespace_config_value(__PACKAGE__, 'plain_ascii') ? (
		fetch_box_character => sub {
			my %symbol = @_;
			my $segments = int keys %symbol;
			if ($segments == 2 && $symbol{down} && ($symbol{left} || $symbol{right})) {
				return '.';
			}
			elsif ($segments == 2 && $symbol{up} && ($symbol{left} || $symbol{right})) {
				return '\'';
			}
			elsif (
				($segments == 2 && $symbol{up} && $symbol{down}) ||
				($segments == 1 && $symbol{vertical})
			) {
				return '|';
			}
			elsif (
				($segments == 2 && $symbol{left} && $symbol{right}) ||
				($segments == 1 && $symbol{horizontal})
			) {
				return '-';
			}
			else {
				return '+';
			}
		},
		) : ()),
	);
	$table->add_header({ alignment => $data->{alignment} }, @{ $data->{columns} });
	$table->add_row(@$_) foreach @{ $data->{rows} };

	return $table->render();
}

no Moose::Role;

1;
