use Module::Build;

my $build = Module::Build->new(
	module_name => 'App::AltSQL',
	license     => 'perl',
	sign        => 1,
	configure_requires => {
		'Module::Build' => 0.4,
	},
	build_requires => {
		'Test::More' => 0,
		'Test::Deep' => 0,
		'File::Temp' => 0,
		'Data::Structure::Util' => 0,
	},
	requires => {
		'Moose'            => 2.0600,
		'MooseX::Object::Pluggable' => 0,
		'DBI'              => 0,
		'DBD::mysql'       => 0,
		'Text::CharWidth'  => 0,
		'Text::UnicodeBox' => 0.03,
		'Term::ANSIColor'  => 0.04,
		'Term::ReadLine::Zoid' => 0,
		'Sys::SigAction'   => 0,
		'Hash::Union'      => 0,
		'Getopt::Long'     => 2.38,
 		'Data::Dumper'     => 0,
		'Config::Any'      => 0,
		'JSON'             => 0,
 		'YAML'             => 0,
		'perl'             => '5.8.0',
	},
	suggests => {
		'DateTime'         => 0,
		'JSON::XS'         => 0,
		'DBIx::MyParsePP'  => 0,
		'Text::ASCIITable' => 0,
		'DBD::Pg'          => 0,
		'DBD::SQLite'      => 0,
	},
	create_makefile_pl => 'small',
	meta_merge => {
		resources => {
			repository => "http://github.com/ewaters/altsql-shell",
			homepage => "http://ewaters.github.com/altsql-shell",
			bugtracker => "http://github.com/ewaters/altsql-shell/issues?labels=bug",
		},
	},
);

$build->create_build_script;

