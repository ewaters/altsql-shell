package App::AltSQL::View::Plugin::Color;

=head1 NAME

App::AltSQL::View::Plugin::Color - Colorize the output in a context sensitive way

=head1 DESCRIPTION

This uses the L<App::AltSQL> configuration file for customizing how things are colored.  The default configuration is:

  header_text => {
    default => 'red',
  },
  cell_text => {
    is_null => 'blue',
    is_primary_key => 'bold',
    is_number => 'yellow',
  }

The values are passed to L<Term::ANSIColor> so any supported color may be used.

=cut

use Moose::Role;
use Number::Format qw(:subs);
use Term::ANSIColor qw(color colored);

my %default_config = (
	header_text => {
		default => 'red',
	},
	cell_text => {
		is_null => 'blue',
		is_primary_key => 'bold',
		is_number => 'yellow',
		is_ipv4 => 'magenta',
		is_url => 'cyan',
		is_bool_true => 'green',
		is_bool_false => 'red',
	},
);

sub format_column_cell {
	my ($self, $spec) = @_;

	return colored $spec->{name}, $self->resolve_namespace_config_value(__PACKAGE__, [ 'header_text', 'default' ], \%default_config);
}

sub format_cell {
	my ($self, $value, $spec) = @_;

	my %colors =
		qw(default is_null is_primary_key is_number);

	my $key = 'default';

	if (! defined $value) {
		$value = 'NULL';
		$key = 'is_null';
	}
	elsif ($spec->{is_pri_key}) {
		$key = 'is_primary_key';
	}
	elsif ($spec->{is_num}) {
		$key = 'is_number';
	}
	elsif ($value =~ /^\d+\.\d+\.\d+\.\d+/) {
		$key = 'is_ipv4';
	}
	elsif ($value =~ /^([a-z]+):\/\//) {
		$key = 'is_url';
	}
	elsif ($value eq 'YES' || $value eq 'ON' || $value eq 'ENABLED') {
		$key = 'is_bool_true';
	}
	elsif ($value eq 'NO' || $value eq 'OFF' || $value eq 'DISABLED') {
		$key = 'is_bool_false';
	}
	else {
		$key = 'default';
	}

	if (my $color = $self->resolve_namespace_config_value(__PACKAGE__, ['cell_text', $key], \%default_config)) {
		return colored $value, $color;
	}
	else {
		return $value;
	}
}

no Moose::Role;

=head1 COPYRIGHT

Copyright (c) 2012 Eric Waters and Shutterstock Images (http://shutterstock.com).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
