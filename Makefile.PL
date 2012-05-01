use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME                => 'MySQL::Client',
	AUTHOR              => q{Eric Waters <ewaters@shutterstock.com>},
	VERSION_FROM        => 'lib/MySQL/Client.pm',
	ABSTRACT            => 'MySQL scriptable command line client',
	($ExtUtils::MakeMaker::VERSION >= 6.3002
		? ('LICENSE'=> 'perl')
		: ()),
	PL_FILES            => {},
	PREREQ_PM => {
		'Moose'            => 0,
		'MooseX::Object::Pluggable' => 0,
		'Params::Validate' => 0,
		'DBI'              => 0,
		'DBD::mysql'       => 0,
		'DBIx::MyParsePP'  => 0,
		'Switch'           => 0,
		'Term::ReadLine::Zoid' => 0,
		'JSON::XS'         => 0,
		'Text::ASCIITable' => 0,
		'Term::ANSIColor'  => 0,
		'Sys::SigAction'   => 0,
	},
	dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
	clean               => { FILES => 'media-*' },
);
