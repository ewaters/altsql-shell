requires 'Moose', '2.0600';
requires 'MooseX::Object::Pluggable';
requires 'DBD::mysql';
requires 'Text::CharWidth';
requires 'Text::UnicodeBox';
requires 'Term::ANSIColor';
requires 'Term::ReadLine::Zoid';
requires 'Sys::SigAction';
requires 'Hash::Union';
requires 'Getopt::Long';
requires 'Data::Dumper';
requires 'Config::Any';
requires 'JSON';
requires 'YAML';

on 'test' => sub {
	requires 'Test::More';
	requires 'Test::Deep';
	requires 'File::Temp';
	requires 'Data::Structure::Util';
};

recommends 'DateTime';
recommends 'JSON::XS';
recommends 'DBIx::MyParsePP';
recommends 'Text::ASCIITable';
recommends 'DBD::Pg';
recommends 'DBD::SQLite';
