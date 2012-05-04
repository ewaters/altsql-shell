package App::AltSQL::View::Plugin::UnicodeBox;

use Moose::Role;
use Text::UnicodeBox::Table;

sub _render_table_data {
	my ($self, $data) = @_;

	my $table = Text::UnicodeBox::Table->new();

	$table->add_header({ style => 'heavy' }, @{ $data->{columns} });
	$table->add_row(@$_) foreach @{ $data->{rows} };

	my $pager;

	# less args are:
	#   -F quit if one screen
	#   -R support color
	#   -X don't send termcap init
	#   -S chop long lines; don't wrap long lines
	if ($table->output_width > $self->app->term->get_term_width) {
		$pager = 'less -FRXS';
	}
	elsif (int @{ $data->{rows} } > $self->app->term->get_term_height) {
		$pager = 'less -FRX';
	}

	if ($pager && ! $data->{no_pager}) {
		open my $out, "| $pager" or die "Can't open $pager for pipe: $!";
		binmode $out, ':utf8';
		print $out $table->render();
		close $out;
	}
	else {
		print $table->render();
	}
}

1;
