use Module::Build;

my $build = Module::Build->new(
	module_name => 'App::AltSQL',
	license     => 'perl',
	sign        => 1,
	configure_requires => {
		'Module::Build' => 0.4,
	},
	build_requires => {
		'Test::Most' => 0,
	},
	requires => {
		'Moose'            => 0,
		'MooseX::Object::Pluggable' => 0,
		'Params::Validate' => 0,
		'DBI'              => 0,
		'DBD::mysql'       => 0,
		'DBIx::MyParsePP'  => 0,
		'Term::ReadLine::Zoid' => 0,
		'JSON::XS'         => 0,
		'Text::ASCIITable' => 0,
		'Text::CharWidth'  => 0,
		'Term::ANSIColor'  => 0.04,
		'Sys::SigAction'   => 0,
		'Config::Any'      => 0,
		'Hash::Union'      => 0,
		'Test::Most'       => 0,
		'Getopt::Long'     => 2.38,
		'Text::UnicodeBox' => 0.03,
 		'YAML'             => 0,
 		'Data::Dumper'     => 0,
	},
	create_makefile_pl => 'passthrough',
	create_readme      => 1,
);

$build->create_build_script;
