package MySQL::Client::Role;

use Moose::Role;

has 'app' => (
	is       => 'ro',
	required => 1,
	handles  => [qw(log_info log_debug log_error)],
);

1;
