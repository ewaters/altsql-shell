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
		type => 'misc',
		words => [qw(
			action auto_increment avg avg_row_length
			both 
			change character checksum columns cross
			current_date current_time current_timestamp
			data databases day day_hour day_minute day_second
			delayed delay_key_write describe distinctrow 
			enclosed escaped 
			fields first flush full 
			global grants 
			heap high_priority hosts hour hour_minute hour_second
			ignore infile insert_id isam
			keys kill last_insert_id leading limit lines load local logs long 
			low_priority
			match max_rows middleint min_rows minute minute_second month myisam
			natural no
			optimize optionally outfile
			pack_keys partial password process processlist
			read reload restrict returns right rows
			second show shutdown soname sql_big_result sql_big_selects sql_big_tables sql_log_off
			sql_log_update sql_low_priority_updates sql_select_limit sql_small_result sql_warnings starting
			status straight_join string
			table tables temporary terminated trailing type
			unlock unsigned usage use 
			varbinary variables varying
			write
			year_month
			zerofill
		)],
	},
	{
		color => 'blue',
		type => 'statement',
		words => [qw(
			alter analyze audit begin comment commit delete
			drop execute explain grant insert lock noaudit
			rename revoke rollback savepoint select
			truncate update vacuum
			replace create)],
	},
	{
		color => 'magenta',
		type => 'type',
		words => [qw(
			bigint bit blob bool boolean byte char
			clob date datetime dec decimal enum
			float int int8 integer interval long
			longblob longtext lvarchar mediumblob
			mediumint mediumtext mlslabel money
			multiset nchar number numeric nvarchar
			raw real rowid serial serial8 set
			smallfloat smallint text time
			timestamp tinyblob tinyint tinytext
			varchar varchar2 varray year
			character characters double doubles varying precision)],
	},
	{
		color => 'green',
		type => 'operator',
		words => [qw(
			all and any between case distinct elif else end
			exists if in intersect is like match matches minus
			not or out prior regexp some then union unique when)],
	},
	{
		color => 'cyan',
		type => 'keywords',
		words => [qw(
			access add after aggregate as asc authorization
			begin by cache cascade check cluster collate
			collation column compress conflict connect connection
			constraint current cursor database debug decimal
			default desc each else elsif escape exception
			exclusive explain external file for foreign from function
			group having identified if immediate increment index
			initial inner into is join key left level loop
			maxextents mode modify nocompress nowait object of
			off offline on online option order outer pctfree
			primary privileges procedure public references
			referencing release resource return role row
			rowlabel rownum rows schema session share size
			start successful synonym then to transaction trigger
			uid user using validate values view virtual whenever
			where with)],
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
