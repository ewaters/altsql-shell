use strict;
use warnings;
use Test::Most;

BEGIN {
	use_ok 'App::AltSQL';
}

ok(App::AltSQL->parse_cli_args(), "Can call without arguments");

cmp_deeply(
	App::AltSQL->parse_cli_args([ qw(-u ewaters -ptestpassword -h localhost sakila) ]),
	superhashof({
		user     => 'ewaters',
		password => 'testpassword',
		host     => 'localhost',
		database => 'sakila',
	}),
	'Basic parse_cli_args',
);

cmp_deeply(
	App::AltSQL->parse_cli_args([qw(--port 12345 -A --help)]),
	superhashof({
		port => 12345,
		no_auto_rehash => 1,
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
		host     => 'dev-mysql01.nyc02.shuttercorp.net',
		database => 'shutterstock',
	}),
	'Known failing CLI args'
);

done_testing;
