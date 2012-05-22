use strict;
use warnings;
use Test::More;
use Test::Deep;

BEGIN {
	use_ok 'App::AltSQL';
}

ok(App::AltSQL->parse_cli_args(), "Can call without arguments");

cmp_deeply(
	App::AltSQL->parse_cli_args([ qw(-u ewaters -ptestpassword -h localhost sakila) ]),
	superhashof({
		_model_user     => 'ewaters',
		_model_password => 'testpassword',
		_model_host     => 'localhost',
		_model_database => 'sakila',
	}),
	'Basic parse_cli_args',
);

cmp_deeply(
	App::AltSQL->parse_cli_args([qw(--port 12345 -A --help)]),
	superhashof({
		_model_port => 12345,
		_model_no_auto_rehash => 1,
		help => 1,
	}),
	'Less common arguments',
);

cmp_deeply(
	App::AltSQL->parse_cli_args([qw(--history ~/.my_altsql_history.js)]),
	superhashof({
		_term_history_fn => '~/.my_altsql_history.js',
	}),
	'Arguments from a subclass',
);

cmp_deeply(
	App::AltSQL->parse_cli_args([qw(-h dev-mysql01.nyc02.shuttercorp.net -D shutterstock)]),
	superhashof({
		_model_host     => 'dev-mysql01.nyc02.shuttercorp.net',
		_model_database => 'shutterstock',
	}),
	'Known failing CLI args'
);

done_testing;
