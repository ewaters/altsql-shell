use strict;
use warnings;
use Test::More;
use Test::Deep;
use File::Temp qw(tempfile);
use File::Spec;

use Data::Structure::Util qw( unbless );

BEGIN {
	use_ok 'App::AltSQL';
	use_ok 'App::AltSQL::Model::MySQL';
}

my $app = bless {}, 'App::AltSQL';

{
	my $instance = App::AltSQL::Model::MySQL->new( app => $app );

	my $filename = write_config(<<ENDFILE);
[client]
user = ewaters
password = 12345
host=localhost
database = sakila

ENDFILE

	$instance->read_my_dot_cnf($filename);
	unbless($instance);
	cmp_deeply(
		$instance,
		superhashof({
			user        => 'ewaters',
			password    => '12345',
			host        => 'localhost',
			database    => 'sakila',
		}),
		'Perfectly Simple my.cnf',
	);
	unlink $filename;
}
{
	my $instance = App::AltSQL::Model::MySQL->new( app => $app );

	my $filename = write_config(<<ENDFILE);
[client]
user = ewaters
password = 12345
host = localhost

[mysql]
database = sakila
default-character-set = utf8
prompt = \\u@\\h[\\R:\\m:\\s]>
safe-update = false
ENDFILE

	$instance->read_my_dot_cnf($filename);
	unbless( $instance );
	cmp_deeply(
		$instance,
		superhashof({
			user        => 'ewaters',
			password    => '12345',
			host        => 'localhost',
			database    => 'sakila',
			safe_update => 0,
			prompt      => '\\u@\\h[\\R:\\m:\\s]>',
		}),
		'Multi-section my.cnf',
	);
	unlink $filename;
}
{
	my $instance = App::AltSQL::Model::MySQL->new( app => $app );

	my $filename = write_config(<<ENDFILE);
[client]
user = ewaters
password = 12345
host = localhost

[mysql]
database = sakila
default-character-set = utf8
prompt = \\u@\\h[\\R:\\m:\\s]>
safe-update = false
ENDFILE

	$instance->read_my_dot_cnf($filename);
	unbless($instance);
	cmp_deeply(
		$instance,
		superhashof({
			user        => 'ewaters',
			password    => '12345',
			host        => 'localhost',
			database    => 'sakila',
			safe_update => 0,
			prompt      => '\\u@\\h[\\R:\\m:\\s]>',
		}),
		'Multi-section my.cnf',
	);
	unlink $filename;
}

{
	my $instance = App::AltSQL::Model::MySQL->new( app => $app );

	my $filename = write_config(<<ENDFILE);
[client]

user=firesun
password=password123

[mysql]

#use this to get faster startup and avoid the following message:
#Reading table information for completion of table and column names
#You can turn off this feature to get a quicker startup with -A
skip-auto-rehash

select_limit = 50

#use this to set your initial database
database = sakila
ENDFILE

	$instance->read_my_dot_cnf($filename);
	unbless($instance);
	cmp_deeply(
		$instance,
		superhashof({
			user           => 'firesun',
			password       => 'password123',
			database       => 'sakila',
			no_auto_rehash => 1,
			select_limit   => 50,
		}),
		'Comments and whitespace',
	);
	unlink $filename;
}

{
	my $instance = App::AltSQL::Model::MySQL->new( app => $app );

	my $filename = write_config(<<ENDFILE);
[client]
user = ewaters
password = 12345
host=localhost
database = sakila
mysql_socket = /path/to_socket/socket.sock
skip-auto-rehash

ENDFILE

	$instance->read_my_dot_cnf($filename);
	unbless($instance);
	cmp_deeply(
		$instance,
		superhashof({
			user           => 'ewaters',
			password       => '12345',
			host           => 'localhost',
			database       => 'sakila',
			no_auto_rehash => 1,
			mysql_socket   => '/path/to_socket/socket.sock',
		}),
		'Config with socket',
	);
	unlink $filename;
}

done_testing;

sub write_config {
	my $config = shift;
	my ($fh, $filename) = tempfile(File::Spec->catfile('', 'tmp', 'myXXXX'), SUFFIX => '.cnf');
	print $fh $config;
	close($fh);
	return $filename;
}
