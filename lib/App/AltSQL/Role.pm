package App::AltSQL::Role;

use Moose::Role;

has 'app' => (
	is       => 'ro',
	required => 1,
	handles  => [qw(log_info log_debug log_error get_namespace_config_value resolve_namespace_config_value)],
);

sub setup {
	my $self = shift;
	# Do nothing; leave it to subclasses
}

no Moose::Role;

1;
