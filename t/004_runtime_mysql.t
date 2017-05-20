use strict;
use warnings;
use Test::More;
use Test::Deep;
use Term::ANSIColor;
use Data::Dumper;
use FindBin;
use lib "$FindBin::Bin/lib/";
use My::ModifierResub;
use My::Common;

if (! $ENV{MYSQL_TESTS}) {
	ok 1, "Skipping tests as \$ENV{MYSQL_TESTS} is not set; this is for developer regression testing";
	done_testing;
	exit;
}

BEGIN {
	use_ok 'App::AltSQL';
}

## Setup

%db_config = (
	user     => $ENV{MYSQL_TEST_USER} || 'perl_tester',
	password => $ENV{MYSQL_TEST_PASSWORD} || '',
	database => $ENV{MYSQL_TEST_DB} || 'test_altsql',
	host     => $ENV{MYSQL_TEST_HOST} || 'localhost',
	sql_files => [
		$FindBin::Bin . '/sql/sakila-schema.sql',
		$FindBin::Bin . '/sql/sakila-data.sql',
	],
	mysql_client => $ENV{MYSQL_TEST_CLIENT} || '/opt/local/bin/mysql5',
);

my $app = App::AltSQL->new(
	args => {
		term_class  => 'App::AltSQL::Term',
		model_class => 'App::AltSQL::Model::MySQL',
		view_class  => 'App::AltSQL::View',
		map { +("_model_$_" => $db_config{$_}) }
		qw(user password host)
	},
	config => {
		%App::AltSQL::default_config,
	},
);
isa_ok $app, 'App::AltSQL';

bootstrap_db $app;

# Describe all the modifiers that will be installed around methods
my %setup_modifiers = (
	model => {
		instance => $app->model,
		methods => [qw(handle_sql_input show_sql_error execute_sql update_autocomplete_entries)],
	},
	app => {
		instance => $app,
		methods => [qw(log_error shutdown call_command create_view)],
	},
	view => {
		# instance is mixed in below after create_view
		methods => [qw(render)],
	},
);

# Install modifiers on singleton instances
foreach my $name (qw(model app)) {
	my $data = $setup_modifiers{$name};
	setup_method_modifiers $name, $data;
}

# Ensure that create_view will install modifiers on instance of View class
local $modifiers{"app create_view after"} = sub {
	my $return = shift;
	setup_method_modifiers 'view', {
		%{ $setup_modifiers{'view'} },
		instance => $return->[0],
	};
};

## Ready to do tests

 # Statement parsing in $app->handle_term_input ###

 ## \c

{
	my $resub = modifier_resub skip_orig => 1;
	local $modifiers{'model handle_sql_input before'} = $resub->code;
	$app->handle_term_input('select staff_id from staff\c');
	ok ! $resub->called, "Ending a statement with \\c doesn't execute the statement";
}

 ## \G

{
	my $resub = modifier_resub skip_orig => 1;
	local $modifiers{'model handle_sql_input before'} = $resub->code;
	$app->handle_term_input('select staff_id from staff\G');
	ok $resub->last_args->[1]{one_row_per_column}, "Ending a statement with \\G adds 'one_row_per_column' flag to model->handle_sql_input";
}

 ## normal statement

{
	my $resub = modifier_resub skip_orig => 1;
	local $modifiers{'model handle_sql_input before'} = $resub->code;
	$app->handle_term_input('select staff_id from staff;');
	is $resub->last_args->[0], 'select staff_id from staff',  "Ending a statement with ; calls model->handle_sql_input with SQL";
}

 ## exit;

{
	my $resub = modifier_resub skip_orig => 1;
	local $modifiers{'app shutdown before'} = $resub->code;
	$app->handle_term_input('exit;');
	ok $resub->called, "exit; calls shutdown()";
}

 ## % eval

{
	my $resub = modifier_resub skip_orig => 1;
	local $modifiers{'app log_error before'} = $resub->code;
	$app->handle_term_input('% die "eval some perl code\n";');
	is $resub->last_args->[0], "eval some perl code\n", "Calling a statement with '%' eval's it and calls log_error with exceptions";
}

 ## call_command()

{
	my $resub = modifier_resub skip_orig => 1, return_value => [ 1 ]; # true return value will consider this handled
	local $modifiers{'app call_command before'} = $resub->code;
	$app->handle_term_input('.my_SPECIAL_command has some args');
	is_deeply $resub->last_args, ['my_special_command', '.my_SPECIAL_command has some args'],
		"Any statement starting with a period is first checked against call_command() to check plugins, lower cased and without a period";
}

 # SQL handling in model->handle_sql_input() ###

 ## Invalid syntax

if ($app->model->sql_parser) {
	my $resub = modifier_resub skip_orig => 1;
	local $modifiers{'model show_sql_error before'} = $resub->code;
	$app->model->handle_sql_input('this is invalid syntax');
	is_deeply $resub->last_args, ['this is invalid syntax', 4, 1],
		"Invalid syntax results in show_sql_error() with input, pos and line number of error";
}

 ## Valid syntax

{
	my $resub = modifier_resub skip_orig => 1;
	local $modifiers{'model execute_sql before'} = $resub->code;
	$app->model->handle_sql_input('select id from staff');
	is_deeply $resub->last_args, ['select id from staff'], "Valid syntax calls execute_sql()";
}

 ## use database and autocomplete

{
	my $resub = modifier_resub skip_orig => 1;
	local $modifiers{'model update_autocomplete_entries before'} = $resub->code;
	# Don't call render()
	local $modifiers{'view render before'} = modifier_resub(skip_orig => 1)->code;
	$app->model->handle_sql_input('use test');
	is_deeply $resub->last_args, ['test'], "'use test' calls update_autocomplete_entries('test')";
	$app->model->execute_sql("use $db_config{database}"); # reset
}

 ## create_view

{
	my $resub = modifier_resub;
	local $modifiers{'app create_view before'} = $resub->code;
	# Don't call render()
	local $modifiers{'view render before'} = modifier_resub(skip_orig => 1)->code;
	my $view = $app->model->handle_sql_input('select staff_id from staff');

	cmp_deeply { @{ $resub->last_args } }, superhashof({
			verb => 'select',
			column_meta => superhashof({
				is_key => [ 1 ],
			}),
		}), "create_view() args";

	cmp_deeply $view->table_data, superhashof({
			columns => [superhashof({
				name => 'staff_id',
				nullable => undef,
				# Keys mapped from mysql_*
				is_key => 1,
				is_num => 1, 
			})],
		}), "View is created with mysql meta data in columns array";

	cmp_deeply $view->footer, re(qr/^2 rows in set/), "Rows in set footer";

	$view = $app->model->handle_sql_input('select staff_id from staff where staff_id > 10');
	cmp_deeply $view->buffer, re(qr/^Empty set/), "Empty set";
}

## Done with tests

done_testing;
