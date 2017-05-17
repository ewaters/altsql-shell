package App::AltSQL::Model;

use Moose;

with 'App::AltSQL::Role';
with 'MooseX::Object::Pluggable';

has 'dbh'        => (is => 'rw');
has 'current_database' => (is => 'rw');

no Moose;
__PACKAGE__->meta->make_immutable();

sub show_sql_error {
	my ($self, $input, $char_number, $line_number) = @_;

	my @lines = split /\n/, $input;
	my $line = $lines[ $line_number - 1 ];
	$self->log_error("There was an error parsing the SQL statement on line $line_number:");
	$self->log_error($line);
	$self->log_error(('-' x ($char_number - 1)) . '^');
}

sub execute_sql {
	my ($self, $input) = @_;

	my $sth = $self->dbh->prepare($input);
	$sth->execute() if $sth;

	if (my $error = $self->dbh->errstr || $@) {
		$self->log_error($error);
		return;
	}

	return $sth;
}

sub is_end_of_statement {
	my ($self, $line) = @_;

	# first we parse to strip the strings and quotes
	# to prevent characters like ; appearing within strings
	# from making us incorrectly detect the end of the
	# statement.
	my @chars = split //, $line;
	my @sanitized_string;

	my $in_something = '';
	my $last_char = '';
	CHAR: while(my $char = shift @chars) {
		if ($in_something) {
			if ($last_char eq '\\' && $in_something =~ /["'`]/) {
				# this character is escaped. lets ignore it.
				$last_char = '';
				next CHAR;
			}
			if ($char eq $in_something) {
				$in_something = '';
			}
			if ($in_something eq '/*' && $char eq '/' && $last_char eq '*') {
				$in_something = '';
			}
		}
		else {
			for my $start (qw/' " `/) {
				if ($char eq $start) {
					if ($last_char eq '\\') {
						last;
						# it's escaped
					}
					$in_something = $start;
				}
			}
			if ($char eq '*') {
				if ($last_char eq '/') {
					$in_something = '/*';
					pop @sanitized_string;
				}
			}
			if ($char eq '-') {
				if ($last_char eq '-') {
					$in_something = '--';
					pop @sanitized_string;
				}
			}
			unless($in_something) {
				push @sanitized_string, $char;
			}
		}
		$last_char = $char;
	}
	if ($in_something eq '--') {
		$in_something = '';
	}
    return 0 if $in_something;

	$line = join '', @sanitized_string;
    # If the buffer ends in ';' or '\G', or
    # if they've typed the bare word 'quit' or 'exit', accept the buffer
	if ($line =~ m{(;|\\G|\\c)\s*$} || $line =~ m{^\s*(quit|exit)\s*$} || $line =~ m{^\s*$}) {
		return 1;
	}
	else {
		return 0;
	}
}

1;
