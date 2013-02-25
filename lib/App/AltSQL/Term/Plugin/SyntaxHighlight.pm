package App::AltSQL::Term::Plugin::SyntaxHighlight;

=head1 NAME

App::AltSQL::Term::Plugin::SyntaxHighlight - Provide syntax-sensitive highlighting while you type

=head1 DESCRIPTION

Perform live syntax highlighting while you type.

This module requires features in L<Term::ReadLine::Zoid> that are not yet in the upstream release.  If you don't want to wait until this module is updated you can install the developer release from here: L<https://github.com/ewaters/Term-ReadLine-Zoid>.  This degrades safely without the updated module.

=cut

use Moose::Role;
use Term::ANSIColor qw(color colored);

# Very very basic keyword highlighting
my @input_highlighting = (
	{
		color => 'yellow',
		words => [qw(
			action add after aggregate all alter as asc auto_increment avg avg_row_length
			both by
			cascade change character check checksum column columns comment constraint create cross
			current_date current_time current_timestamp
			data database databases day day_hour day_minute day_second
			default delayed delay_key_write delete desc describe distinct distinctrow drop
			enclosed escape escaped explain
			fields file first flush for foreign from full function
			global grant grants group
			having heap high_priority hosts hour hour_minute hour_second
			identified ignore index infile inner insert insert_id into isam
			join
			key keys kill last_insert_id leading left limit lines load local lock logs long 
			low_priority
			match max_rows middleint min_rows minute minute_second modify month myisam
			natural no
			on optimize option optionally order outer outfile
			pack_keys partial password primary privileges procedure process processlist
			read references reload rename replace restrict returns revoke right row rows
			second select show shutdown soname sql_big_result sql_big_selects sql_big_tables sql_log_off
			sql_log_update sql_low_priority_updates sql_select_limit sql_small_result sql_warnings starting
			status straight_join string
			table tables temporary terminated to trailing type
			unique unlock unsigned update usage use using
			values varbinary variables varying
			where with write
			year_month
			zerofill
		)],
	},
);

# Compile the above into regex
foreach my $syntax_block (@input_highlighting) {
	my $words = join '|', @{ $syntax_block->{words} };
	$syntax_block->{regex} = qr/\b($words)\b/i;
}

after _build_term => sub {
	my $self = shift;

	$self->{term}->Attribs->{lines_preprocess_function} = sub {
		my ($lines, $pos) = @_;
		for my $i (0..$#{ $lines }) {
			# Color the main color words (just for the fun)
			foreach my $syntax_block (@input_highlighting) {
				$lines->[$i] =~ s/($$syntax_block{regex})/colored($1, $syntax_block->{color})/eg;
			}
		}
	};
};

no Moose::Role;

=head1 COPYRIGHT

Copyright (c) 2012 Eric Waters and Shutterstock Images (http://shutterstock.com).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
