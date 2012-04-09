package MySQL::ANSIClient;

use strict;
use warnings;
use Getopt::Long;
use Params::Validate;
use DBI;
use Data::Dumper;
use DBIx::MyParsePP;
use Switch 'Perl6';
use Time::HiRes qw(gettimeofday tv_interval);

## Configure

sub help_text {

}

sub capture_command_line_args {
	my $class = shift;
	my %args;
	GetOptions(
		'host|h=s' => \$args{host},
		'user|u=s' => \$args{user},
		'pass|p=i' => \$args{password},
		'database|d=s' => \$args{database},
		'port|P=s' => \$args{port},
		'help|?'   => \$args{help},
	);
	if (@ARGV && int @ARGV == 1) {
		$args{database} = $ARGV[0];
	}
	if ($args{help}) {
		print <<EOF;

  -h --host HOSTNAME
  -u --user USERNAME
  -p --pass PASSWORD
  -P --port PORT
  -d --database DATABASE
  -? --help
EOF
		exit;
	}
	return %args;
}

sub new {
	my $class = shift;
	my %args = validate(@_, {
		term_class => { default => 'MySQL::ANSIClient::Term' },
		table_class => { default => 'MySQL::ANSIClient::Table' },
		args => 1,
	});
	my $self = bless \%args, $class;

	$self->db_connect();

	return $self;
}

sub db_connect {
	my $self = shift;
	my $dsn = 'DBI:mysql:' . join (';',
		map { "$_;$self->{args}{$_}" }
		grep { defined $self->{args}{$_} }
		qw(database host port)
	);
	$self->{dbh} = DBI->connect($dsn, $self->{args}{user}, $self->{args}{password}, {
		PrintError => 0,
	}) or die $DBI::errstr . "\n";
}

sub new_from_cli {
	my $class = shift;

	my %args = $class->capture_command_line_args;
	if ($args{help}) {
		$class->log_info($class->help_text);
		exit;
	}

	return $class->new(args => \%args);
}

## Main

sub run {
	my $self = shift;

	$self->log_info("Starting ".__PACKAGE__);

	## Create a terminal and begin to read from it

	my $term_class = $self->{term_class};
	eval "require $term_class";
	die $@ if $@;
	my $term = $term_class->new($self);

	my $table_class = $self->{table_class};
	eval "require $table_class";
	die $@ if $@;
	my $table = $table_class->new($self);

	my $parser = DBIx::MyParsePP->new();

	my $input;
	while (defined ($input = $term->readline())) {
		# Next if Ctrl-C or if user typed nothing
		if (! length $input) {
			next;
		}

		# Extract out \G
		my %render_opts;
		if ($input =~ s/\\G$//) {
			$render_opts{one_row_per_table} = 1;
		}

		# Attempt to parse the input with a SQL parser
		my $parsed = $parser->parse($input);
		if (! defined $parsed->root) {
			$self->log_error(sprintf "Error at pos %d, line %s", $parsed->pos, $parsed->line);
			next;
		}

		# Based on the context of what type of action is being performed, print a table or print just a success/failure
		my $statement = $parsed->root->extract('statement');
		if (! $statement) {
			$self->log_error("Not sure what to do with this; no 'statement' in the parse tree");
			next;
		}

		my $sql = $parsed->toString;
		given (my $verb = $statement->children->[0]) {
			when [qw( select describe explain show )] {
				my %data = (
					timing => { start => scalar gettimeofday },
				);

				my $sth = $self->{dbh}->prepare($sql);
				$sth->execute();

				foreach my $i (0..$sth->{NUM_OF_FIELDS} - 1) {
					push @{ $data{columns} }, {
						name      => $sth->{NAME}[$i],
						type      => $sth->{TYPE}[$i],
						precision => $sth->{PRECISION}[$i],
						scale     => $sth->{SCALE}[$i],
						nullable  => $sth->{NULLABLE}[$i] || undef,
					};
				}
				
				$data{rows} = $sth->fetchall_arrayref;
				$data{timing}{stop} = scalar gettimeofday;

				$table->render(\%data);
			}
			when [qw( use create )] {
				$self->{dbh}->do($sql);
			}
			default {
				$self->log_info("I don't know how to handle '$verb'");
			}
		}
	}
}

## Output display

sub log_info {
	my ($self, $message) = @_;
	print $message . "\n";
}

sub log_debug {
	return log_info(@_);
}

sub log_error {
	return log_info(@_);
}

1;
