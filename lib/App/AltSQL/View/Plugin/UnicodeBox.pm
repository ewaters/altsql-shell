package App::AltSQL::View::Plugin::UnicodeBox;

use Moose::Role;
use Text::UnicodeBox::Table;
no Moose::Role;

sub _render_table_data {
	my ($self, $data) = @_;

	my $table = Text::UnicodeBox::Table->new(
		split_lines => 1,
	);
	$table->add_header({ style => 'heavy' }, @{ $data->{columns} });
	$table->add_row(@$_) foreach @{ $data->{rows} };

	return $table->render();
}

1;
