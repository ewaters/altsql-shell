package My::Common;

use strict;
use warnings;
use base qw(Exporter);

our @EXPORT = qw(%db_config bootstrap_db);

our %db_config;

sub load_sql_file_mysql {
	my $file = shift;
	my @cmd = ($db_config{mysql_client},
		'-u', $db_config{user},
		($db_config{password} ? (
		'-p' . $db_config{password},
		) : ()),
		'-h', $db_config{host},
		$db_config{database},
		'<',
		$file,
	);
	my $cmd = join ' ', @cmd;

	print "Running $cmd\n";
	system $cmd;
}

sub bootstrap_db ($) {
	my $app = shift;
	my $dbh = $app->model->dbh;

	if (! $ENV{SKIP_BOOTSTRAP}) {
		if ($app->args->model_class eq 'App::AltSQL::Model::MySQL') {
			$dbh->do("drop database if exists $db_config{database}");
			$dbh->do("create database $db_config{database}");

			load_sql_file_mysql($_) foreach @{ $db_config{sql_files} };
		}
	}

	$dbh->do("use $db_config{database}");
}

1;
