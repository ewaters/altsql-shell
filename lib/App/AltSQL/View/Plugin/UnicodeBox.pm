package App::AltSQL::View::Plugin::UnicodeBox;

use Moose::Role;
use Text::UnicodeBox::Table;
no Moose::Role;

my %default_config = (
	style => 'heavy_header',
	split_lines => 1,
);

sub _render_table_data {
	my ($self, $data) = @_;

	my $table = Text::UnicodeBox::Table->new(
		split_lines => $self->resolve_namespace_config_value(__PACKAGE__, 'split_lines', \%default_config),
		style       => $self->resolve_namespace_config_value(__PACKAGE__, 'style', \%default_config),
	);
	$table->add_header({ alignment => $data->{alignment} }, @{ $data->{columns} });
	$table->add_row(@$_) foreach @{ $data->{rows} };

	return $table->render();
}

1;
