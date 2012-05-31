package App::AltSQL::View::Plugin::UnicodeBox;

=head1 NAME

App::AltSQL::View::Plugin::UnicodeBox - Use Text::UnicodeBox::Table instead of Text::ASCIITable for table output

=head1 DESCRIPTION

This uses the L<App::AltSQL> configuration file for customizing how things are colored.  The default configuration is:

  style => 'heavy_header',
  split_lines => 1,
  plain_ascii => 0,
  header_reminder => 100,

The values 'style' and 'split_lines' are passed to L<Text::UnicodeBox::Table>.  'plain_ascii' will toggle a non-unicode table output but still benefit from the features of L<Text::UnicodeBox::Table>

=cut

use Moose::Role;
use Text::UnicodeBox::Table;

my %default_config = (
	style => 'heavy_header',
	split_lines => 1,
	plain_ascii => 0,
	header_reminder => 100,
);

sub _render_table_data {
	my ($self, $data) = @_;

	my $table = Text::UnicodeBox::Table->new(
		split_lines => $self->resolve_namespace_config_value(__PACKAGE__, 'split_lines', \%default_config),
		style       => $self->resolve_namespace_config_value(__PACKAGE__, 'style', \%default_config),
		($self->resolve_namespace_config_value(__PACKAGE__, 'plain_ascii', \%default_config) ? (
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

	my $header_reminder_frequency = $self->resolve_namespace_config_value(__PACKAGE__, 'header_reminder', \%default_config);

	$table->add_header({ alignment => $data->{alignment} }, @{ $data->{columns} });

	my $row_count = 0;
	my $last_header_at = 0;
	foreach my $row (@{ $data->{rows} }) {
		$table->add_row(@$row);
		if ($header_reminder_frequency && (++$row_count - $last_header_at > $header_reminder_frequency)) {
			$table->add_header(@{ $data->{columns} });
			$last_header_at = $row_count;
		}
	}

	return $table->render();
}

no Moose::Role;

=head1 DEVELOPMENT

This module is being developed via a git repository publicly available at http://github.com/ewaters/altsql-shell.  I encourage anyone who is interested to fork my code and contribute bug fixes or new features, or just have fun and be creative.

=head1 COPYRIGHT

Copyright (c) 2012 Eric Waters and Shutterstock Images (http://shutterstock.com).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
