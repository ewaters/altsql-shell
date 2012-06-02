use strict;
use warnings;
use Test::More;
use Test::Deep;
use Term::ANSIColor;
use Data::Dumper;
use FindBin;

if (! $ENV{MYSQL_TESTS}) {
	ok 1, "Skipping tests as \$ENV{MYSQL_TESTS} is not set; this is for developer regression testing";
	done_testing;
	exit;
}

BEGIN {
	use_ok 'App::AltSQL';
}

## Setup

my %config = (
	user     => 'perl_tester',
	password => '',
	database => 'test_altsql',
	host     => 'localhost',
	sql_files => [
		$FindBin::Bin . '/sql/sakila-schema.sql',
		$FindBin::Bin . '/sql/sakila-data.sql',
	],
	mysql_client => '/opt/local/bin/mysql5',
);

my $app = App::AltSQL->new(
	args => {
		term_class  => 'App::AltSQL::Term',
		model_class => 'App::AltSQL::Model::MySQL',
		view_class  => 'App::AltSQL::View',
		map { +("_model_$_" => $config{$_}) }
		qw(user password host)
	},
	config => {
		%App::AltSQL::default_config,
	},
);
isa_ok $app, 'App::AltSQL';

my $dbh = $app->model->dbh;

if (! $ENV{SKIP_BOOTSTRAP}) {
	$dbh->do("drop database if exists $config{database}");
	$dbh->do("create database $config{database}");

	load_sql_file($_) foreach @{ $config{sql_files} };
}

$dbh->do("use $config{database}");

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

# Define hash that'll be used for local overrides
my %modifiers;

# Install modifiers on singleton instances
foreach my $name (qw(model app)) {
	my $data = $setup_modifiers{$name};
	setup_method_modifiers($name, $data);
}

# Ensure that create_view will install modifiers on instance of View class
local $modifiers{"app create_view after"} = sub {
	my $return = shift;
	setup_method_modifiers('view', {
		%{ $setup_modifiers{'view'} },
		instance => $return->[0],
	});
};

## Ready to do tests

 # Statement parsing in $app->handle_term_input ###

 ## \c

{
	my $ok = 1;
	local $modifiers{'model handle_sql_input before'} = sub {
		$ok = 0;
		return 1;
	};
	$app->handle_term_input('select staff_id from staff\c');
	ok $ok, "Ending a statement with \\c doesn't execute the statement";
}

 ## \G

{
	my $ok;
	local $modifiers{'model handle_sql_input before'} = sub {
		my ($return, $input, $render_opts) = @_;
		$ok = 1 if $render_opts->{one_row_per_column};
		return 1;
	};
	$app->handle_term_input('select staff_id from staff\G');
	ok $ok, "Ending a statement with \\G adds 'one_row_per_column' flag to model->handle_sql_input";
}

 ## normal statement

{
	my $sql;
	local $modifiers{'model handle_sql_input before'} = sub {
		my ($return, $input, $render_opts) = @_;
		$sql = $input;
		return 1;
	};
	$app->handle_term_input('select staff_id from staff;');
	is $sql, 'select staff_id from staff',  "Ending a statement with ; calls model->handle_sql_input with SQL";
}

 ## exit;

{
	my $ok;
	local $modifiers{'app shutdown before'} = sub {
		$ok = 1;
		return 1;
	};
	$app->handle_term_input('exit;');
	ok $ok, "exit; calls shutdown()";
}

 ## % eval

{
	my $error;
	local $modifiers{'app log_error before'} = sub {
		$error = $_[1];
		return 1;
	};
	$app->handle_term_input('% die "eval some perl code\n";');
	is $error, "eval some perl code\n", "Calling a statement with '%' eval's it and calls log_error with exceptions";
}

 ## call_command()

{
	my $args;
	local $modifiers{'app call_command before'} = sub {
		my $return = shift;
		$args = [ @_ ];
		$return->[0] = 'handled';
		return 1;
	};
	$app->handle_term_input('.my_SPECIAL_command has some args');
	is_deeply $args, ['my_special_command', '.my_SPECIAL_command has some args'],
		"Any statement starting with a period is first checked against call_command() to check plugins, lower cased and without a period";
}

 # SQL handling in model->handle_sql_input() ###

 ## Invalid syntax

if ($app->model->sql_parser) {
	my $args;
	local $modifiers{'model show_sql_error before'} = sub {
		my $return = shift;
		$args = [ @_ ];
		return 1;
	};
	$app->model->handle_sql_input('this is invalid syntax');
	is_deeply $args, ['this is invalid syntax', 4, 1],
		"Invalid syntax results in show_sql_error() with input, pos and line number of error";
}

 ## Valid syntax

{
	my $args;
	local $modifiers{'model execute_sql before'} = sub {
		my $return = shift;
		$args = [ @_ ];
		return 1;
	};
	$app->model->handle_sql_input('select id from staff');
	is_deeply $args, ['select id from staff'], "Valid syntax calls execute_sql()";
}

 ## use database and autocomplete

{
	my $args;
	local $modifiers{'model update_autocomplete_entries before'} = sub {
		my $return = shift;
		$args = [ @_ ];
		return 1;
	};
	# Don't call render()
	local $modifiers{'view render before'} = sub { return 1; };
	$app->model->handle_sql_input('use test');
	is_deeply $args, ['test'], "'use test' calls update_autocomplete_entries('test')";
	$app->model->execute_sql("use $config{database}"); # reset
}

 ## create_view

{
	my $args;
	local $modifiers{'app create_view before'} = sub {
		my $return = shift;
		$args = [ @_ ];
		return 0; # Call the $orig
	};
	# Don't call render()
	local $modifiers{'view render before'} = sub { return 1; };
	my $view = $app->model->handle_sql_input('select staff_id from staff');

	cmp_deeply { @$args }, superhashof({
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

sub load_sql_file {
	my $file = shift;
	my @cmd = ($config{mysql_client},
		'-u', $config{user},
		($config{password} ? (
		'-p' . $config{password},
		) : ()),
		'-h', $config{host},
		$config{database},
		'<',
		$file,
	);
	my $cmd = join ' ', @cmd;

	print "Running $cmd\n";
	system $cmd;
}

sub setup_method_modifiers {
	my ($name, $data) = @_;
	foreach my $method (@{ $data->{methods} }) {
		# Setup default, no-op sub refs
		$modifiers{"$name $method before"} ||= sub {};
		$modifiers{"$name $method after"} ||= sub {};

		my $meta_role = Moose::Meta::Role->create_anon_role();
		$meta_role->add_around_method_modifier($method => sub {
			my ($orig, $self, @args) = (shift, shift, @_);

			# Try the 'before' modifier and return @return if it returns true
			my @return;
			if ($modifiers{"$name $method before"}(\@return, @args)) {
				return wantarray ? @return : $return[0];
			}

			# Call original function
			@return = wantarray ? ($self->$orig(@args)) : (scalar $self->$orig(@args));

			$modifiers{"$name $method after"}(\@return);

			return wantarray ? @return : $return[0];
		});
		$meta_role->apply($data->{instance});
	}
}
