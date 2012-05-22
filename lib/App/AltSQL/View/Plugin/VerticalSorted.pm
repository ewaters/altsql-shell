package App::AltSQL::View::Plugin::VerticalSorted;

use Moose::Role;

around render_one_row_per_column => sub {
	my ($orig, $self, $data) = @_;
	$data = $self->table_data;
	my %data = %$data;

	# Determine a map to remap the columns and rows

	my @positions = 0..$#{ $data{columns} };
	my @sorted_positions = sort { $data{columns}[$a]{name} cmp $data{columns}[$b]{name} } @positions;
	my %new_position_map;
	@new_position_map{ @positions } = @sorted_positions;

	# Remap columns

	$data{columns} = [
		map { $data{columns}[ $new_position_map{$_} ] } 
		@positions
	];

	# Remap rows

	foreach my $row_idx (0..$#{ $data{rows} }) {
		my $row = $data{rows}[$row_idx];
		$data{rows}[ $row_idx ] = [
			map { $row->[ $new_position_map{$_} ] } 
			@positions
		];
	}

	$self->$orig(\%data);
};

no Moose::Role;

=head1 COPYRIGHT

Copyright (c) 2012 Eric Waters and Shutterstock Images (http://shutterstock.com).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
