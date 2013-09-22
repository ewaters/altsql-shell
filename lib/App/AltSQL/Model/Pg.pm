package App::AltSQL::Model::Pg;

=head1 NAME

App::AltSQL::Model::Pg

=head1 DESCRIPTION

Initial attempt at a Postgres model class

=cut

use Moose;
use DBI;
use Sys::SigAction qw(set_sig_handler);
use Time::HiRes qw(gettimeofday tv_interval);

extends 'App::AltSQL::Model';

has [qw(host user password database port)] => ( is => 'ro' );

sub args_spec {
	return (
		host => {
			cli         => 'host|h=s',
			help        => '-h HOSTNAME | --host HOSTNAME',
			description => 'The hostname for the database server',
		},
		user => {
			cli         => 'user|u=s',
			help        => '-u USERNAME | --user USERNAME',
			description => 'The username to authenticate as',
		},
		password => {
			help        => '-p | --password=PASSWORD | -pPASSWORD',
			description => 'The password to authenticate with',
		},
		database => {
			cli         => 'database|d=s',
			help        => '-d DATABASE | --database DATABASE',
			description => 'The database to use once connected',
		},
		port => {
			cli         => 'port=i',
			help        => '--port PORT',
			description => 'The port to use for the database server',
		},
	);
}

sub db_connect {
	my $self = shift;
	my $dsn = 'DBI:Pg:' . join (';',
		map { "$_=" . $self->$_ }
		grep { defined $self->$_ }
		qw(database host port)
	);
	my $dbh = DBI->connect($dsn, $self->user, $self->password, {
		PrintError => 0,
	}) or die $DBI::errstr . "\nDSN used: '$dsn'\n";
	$self->dbh($dbh);

	if ($self->database) {
		$self->current_database($self->database);
	}
}

sub handle_sql_input {
	my ($self, $input, $render_opts) = @_;

	# Figure out the verb of the SQL by either using regex or a parser.  If we
	# use the parser, we get error checking here instead of the server.
	my $verb;
	($verb, undef) = split /\s+/, $input, 2;

	# Run the SQL
	
	my $t0 = gettimeofday;

	my $sth = $self->execute_sql($input);
	return unless $sth; # error may have been reached (and reported)

	# Track which database we're in for autocomplete
	if (my ($database) = $input =~ /^use \s+ (\S+)$/ix) {
		$self->current_database($database);
	}

	my %timing = ( prepare_execute => gettimeofday - $t0 );

	my $view = $self->app->create_view(
		sth => $sth,
		timing => \%timing,
		verb => $verb,
	);
	$view->render(%$render_opts);

	return $view;
}

no Moose;
__PACKAGE__->meta->make_immutable;

=head1 COPYRIGHT

Copyright (c) 2012 Eric Waters and Shutterstock Images (http://shutterstock.com).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
