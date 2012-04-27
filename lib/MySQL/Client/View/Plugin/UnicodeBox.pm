package MySQL::Client::View::Plugin::UnicodeBox;

use Moose::Role;
use Text::UnicodeBox::Table;

sub _render_table_data {
	my ($self, $data) = @_;

	my $table = Text::UnicodeBox::Table->new();

	$table->add_header({ style => 'heavy' }, @{ $data->{columns} });
	$table->add_row(@$_) foreach @{ $data->{rows} };

	print $table->render();
}

1;
