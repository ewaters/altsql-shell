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

=head1 COLOURS

Lots more colours. Unwieldy though, needs to be refactored

=cut

my %default_config = (
	header_text => {
		default => 'red',
	},
	cell_text => {
		is_null => 'blue',
		is_primary_key => 'underline bold',
		is_primary_key_number => 'yellow underline',
		is_primary_key_ipv4 => 'magenta underline',
		is_primary_key_aa => 'underline bold black on_white',
		is_key => 'white underline',
		is_key_number => 'yellow underline',
		is_key_ipv4 => 'magenta underline',
		is_number => 'yellow',
		is_ipv4 => 'magenta',
		is_url => 'cyan',
		is_bool_true => 'green',
		is_bool_false => 'red',
	},
);

sub format_column_cell {
	my ($self, $spec) = @_;

	my $value = $spec->{name};

	if ($spec->{is_pri_key}) {
		$value = $value . ' [PRI]';
	}
	elsif ($spec->{is_key}) {
		$value = $value . ' [FK]';
	}

	if ($spec->{is_auto_increment}) {
		$value = $value . ' [AI]'
	}

	return colored $value, $self->resolve_namespace_config_value(__PACKAGE__, [ 'header_text', 'default' ], \%default_config);
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
		if ($spec->{is_auto_increment}) {
			$key = $key . '_aa';
		}
		elsif ($spec->{is_num}) {
			$key = $key . '_number';
		}
		elsif ($value =~ /^\d+\.\d+\.\d+\.\d+/) {
			$key = $key . '_ipv4';
		}
	}
	elsif ($spec->{is_key}) {
		$key = 'is_key';
		if ($spec->{is_num}) {
			$key = $key . '_number';
		}
		elsif ($value =~ /^\d+\.\d+\.\d+\.\d+/) {
			$key = $key . '_ipv4';
		}
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
