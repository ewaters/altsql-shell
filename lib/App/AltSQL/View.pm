package App::AltSQL::View;

=head1 NAME

App::AltSQL::View

=head1 DESCRIPTION

This is an internal class used by L<App::AltSQL> to capture the output of a DBI statement handler and express it to the user somehow.  It does this mainly with L<Text::UnicodeBox::Table>, and is currently MySQL specific.

=cut

use Moose;
use Data::Dumper;
use Text::ASCIITable;
use Text::CharWidth qw(mbswidth);
use Time::HiRes qw(gettimeofday);
use Params::Validate;
use List::Util qw(sum max);

with 'App::AltSQL::Role';
with 'MooseX::Object::Pluggable';

has 'timing' => ( is => 'rw' );
has 'verb'   => ( is => 'rw' );

has 'buffer' => ( is => 'rw' );
has 'table_data' => ( is => 'rw' );
has 'footer' => ( is => 'rw' );

sub args_spec {
	return (
	);
}

around BUILDARGS => sub {
	my $orig = shift;
	my $class = shift;
	my %args = validate(@_, {
		app    => 1,
		timing => 1,
		verb   => 1,
		sth    => 1,
	});
	my $sth = delete $args{sth};

	if ($args{verb} eq 'use') {
		$args{buffer} = 'Database changed';
		return $class->$orig(\%args);
	}

	if (! $sth->{NUM_OF_FIELDS}) {
		$args{buffer} = sprintf "Query OK, %d row%s affected (%s)\n", $sth->rows, ($sth->rows > 1 ? 's' : ''), _describe_timing($args{timing});
		if ($args{verb} ne 'insert') {
			$args{buffer} .= sprintf "Records: %d  Warnings: %d\n", $sth->rows, $sth->{mysql_warning_count};
		}
		$args{buffer} .= "\n";
		return $class->$orig(\%args);
	}

	my %table_data = (
		columns => [],
		rows    => [],
	);
	$args{table_data} = \%table_data;

	# Populate table_data{columns}
	my %mysql_meta = (
		map { my $key = $_; $key =~ s/^mysql_//; +($key => $sth->{$_}) }
		qw(mysql_is_blob mysql_is_key mysql_is_num mysql_is_pri_key mysql_is_auto_increment mysql_length mysql_max_length)
	);
	foreach my $i (0..$sth->{NUM_OF_FIELDS} - 1) {
		push @{ $table_data{columns} }, {
			name      => $sth->{NAME}[$i],
			type      => $sth->{TYPE}[$i],
			precision => $sth->{PRECISION}[$i],
			scale     => $sth->{SCALE}[$i],
			nullable  => $sth->{NULLABLE}[$i] || undef,
			map { $_ => $mysql_meta{$_}[$i] } keys %mysql_meta
		};
	}

	# Populate table_data{rows}
	my $t0 = gettimeofday;
	$table_data{rows} = $sth->fetchall_arrayref;
	$args{timing}{fetchall} = gettimeofday - $t0;

	# Return if no rows in result
	if (int @{ $table_data{rows} } == 0) {
		$args{buffer} = sprintf "Empty set (%s)\n\n", _describe_timing($args{timing});
		return $class->$orig(\%args);
	}

	$args{footer} = sprintf "%d rows in set (%s)\n\n", int @{ $table_data{rows} }, _describe_timing($args{timing});

	return $class->$orig(\%args);
};

=head2 render %args

Optionally pass 'no_pager' or 'one_row_per_column'.  Will render the stored buffer by either printing it to the screen or piping it to a pager.

=cut

sub render {
	my $self = shift;
	my %args = validate(@_, {
		no_pager           => 0,
		one_row_per_column => 0,
	});

	# Buffer will be unset unless there is a static result
	my $buffer = $self->buffer;
	if ($buffer) {
		print $buffer;
		return;
	}

	# Otherwise, construct the buffer from rendering the table_data with footer
	if ($args{one_row_per_column}) {
		$buffer = $self->render_one_row_per_column();
	}
	else {
		$buffer = $self->render_table();
	}

	if ($self->footer) {
		$buffer .= $self->footer;
	}

	## Possibly page the output

	my $pager;
	my ($buffer_width, $buffer_height) = _buffer_dimensions(\$buffer);

	# less args are:
	#   -F quit if one screen
	#   -R support color
	#   -X don't send termcap init
	#   -S chop long lines; don't wrap long lines

	if ($buffer_width > $self->app->term->get_term_width) {
		$pager = 'less -FRXS';
	}
	elsif ($buffer_height > $self->app->term->get_term_height) {
		$pager = 'less -FRX';
	}

	if ($pager && ! $args{no_pager}) {
		open my $out, "| $pager" or die "Can't open $pager for pipe: $!";
		binmode $out, ':utf8';
		print $out $buffer;
		close $out;
	}
	else {
		print $buffer;
	}
}

=head2 render_table

Given the table data that was extracted from the statement handler, compose a nicely formatted table for showing to the user.

=cut

sub render_table {
	my $self = shift;
	my $data = $self->table_data;

	my %table = (
		alignment => [ map { $_->{is_num} ? 'right' : 'left' } @{ $data->{columns} } ],
		columns   => [ map { $self->format_column_cell($_) } @{ $data->{columns} } ],
		rows      => [],
	);
	foreach my $row (@{ $data->{rows} }) {
		my @row;
		foreach my $i (0..$#{ $data->{columns} }) {
			push @row, $self->format_cell($row->[$i], $data->{columns}[$i]);
		}
		push @{ $table{rows} }, \@row;
	}

	my $t0 = gettimeofday;
	my $output = $self->_render_table_data(\%table);
	$self->timing->{render_table} = gettimeofday - $t0;
	return $output;
}

sub _render_table_data {
	my ($self, $data) = @_;
	my $table = Text::ASCIITable->new({ allowANSI => 1 });

	$table->setCols(@{ $data->{columns} });
	foreach my $row (@{ $data->{rows} }) {
		$table->addRow(@$row);
	}
	return '' . $table;
}

=head2 render_one_row_column

Rather then using ASCII art to horizontally format each row, use one row of output per cell of data.

=cut

sub render_one_row_per_column {
	my $self = shift;
	my $data = $self->table_data;

	my $max_length_of_column = 0;
	foreach my $column (@{ $data->{columns} }) {
		my $length = length $column->{name};
		$max_length_of_column = $length if ! $max_length_of_column || $max_length_of_column < $length;
	}

	my $output = '';

	my $count = 1;
	foreach my $row (@{ $data->{rows} }) {
		$output .= "*************************** $count. row ***************************\n";
		$count++;

		foreach my $i (0..$#{ $data->{columns} }) {
			my $padding_count = $max_length_of_column - length $data->{columns}[$i]{name};
			$output .= sprintf "%s%s: %s\n",
				(' ' x $padding_count),
				$self->format_column_cell($data->{columns}[$i]),
				$self->format_cell($row->[$i], $data->{columns}[$i]);
		}
	}

	return $output;
}

=head2 format_column_cell \%spec

Given the column specification, format the output for the user.  This would be the header cell of the table.  The specification may have the following keys, which match up with data found in the L<DBI> statement handler.

=over 4

=item name

=item type

=item precision

=item scale

=item nullable

=item is_blob

=item is_key

=item is_num

=item is_pri_key

=item is_auto_increment

=item length

=item max_length

=back

=cut

sub format_column_cell {
	my ($self, $spec) = @_;

	return $spec->{name};
}

=head2 format_cell $value, \%spec

Format the cell $value while knowing the column %spec (same data structure as above)

=cut

sub format_cell {
	my ($self, $value, $spec) = @_;

	return $value;
}

sub _buffer_dimensions {
	my $buffer_ref = shift;

	my $width = 0;
	my $height = 0;

	foreach my $line (split /\n/, $$buffer_ref)	{
		$width = max(mbswidth($line), $width);
		$height++;
	}

	return ($width, $height);
}

sub _describe_timing {
	my $timing = shift;
	my $seconds = sum values %$timing;

	my $minutes;
	if ($seconds > 60) {
		$minutes = sprintf '%d', $seconds / 60;
		$seconds -= $minutes * 60;
	}

	if ($minutes) {
		return sprintf '%d min %d sec', $minutes, $seconds;
	}
	else {
		return sprintf '%.2f sec', $seconds;
	}
}

no Moose;
__PACKAGE__->meta->make_immutable;

=head1 DEVELOPMENT

This module is being developed via a git repository publicly available at http://github.com/ewaters/altsql-shell.  I encourage anyone who is interested to fork my code and contribute bug fixes or new features, or just have fun and be creative.

=head1 COPYRIGHT

Copyright (c) 2012 Eric Waters and Shutterstock Images (http://shutterstock.com).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
