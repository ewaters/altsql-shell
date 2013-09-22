package App::AltSQL::Model::SQLite;

=head1 NAME

App::AltSQL::Model::SQLite

=head1 DESCRIPTION

A model for SQLite.

=cut

use Moose;
use DBI;

extends 'App::AltSQL::Model';

has database => (
	is => 'ro',
);

sub args_spec {
	return (
		database => {
			cli         => 'database|d=s',
			help        => '-d DATABASE | --database DATABASE',
			description => 'The database file to use',
		},
	);
}

sub db_connect {
	my ( $self ) = @_;

	my $dsn = 'DBI:SQLite:dbname=' . $self->database;
	my $dbh = DBI->connect($dsn, undef, undef, {
		PrintError => 1,
		# XXX sqlite-specific options
	}) or die $DBI::errstr . "\nDSN uesd: '$dsn'\n";
	$self->dbh($dbh);

	# XXX update autocomplete/db_types
}	

sub handle_sql_input {
	my ( $self, $input, $render_opts ) = @_;

	my $verb = 'SELECT'; # XXX fix me

	my $sth = $self->execute_sql($input);
	return unless $sth;

	my %timing; # XXX fix me

	my $view = $self->app->create_view(
		sth         => $sth,
		timing      => \%timing,
		verb        => $verb,
		column_meta => {
			# XXX fix me
		},
	);
	$view->render(%$render_opts);

	return $view;
}

no Moose;
__PACKAGE__->meta->make_immutable;

=head1 AUTHOR

Rob Hoelz <rob AT hoelz.ro>

=cut

1;
