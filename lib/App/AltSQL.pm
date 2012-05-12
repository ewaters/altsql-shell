package App::AltSQL;

use Moose;
use Getopt::Long qw(GetOptionsFromArray);
use Params::Validate;
use Data::Dumper;
use Switch 'Perl6';
use Time::HiRes qw(gettimeofday tv_interval);
use Config::Any;
use Hash::Union qw(union);

our $VERSION = 0.01;
our $| = 1;

# Don't emit 'Wide character in output' warnings
binmode STDOUT, ':utf8';

with 'MooseX::Object::Pluggable';

my @_config_stems = ( '/etc/altsql', "$ENV{HOME}/.altsql" );
my %_default_classes = (
	term => 'App::AltSQL::Term',
	view => 'App::AltSQL::View',
	model => 'App::AltSQL::Model::MySQL',
);
has ['term', 'view', 'model']  => (is => 'ro');
has ['args', 'config'] => (is => 'rw');

no Moose;
__PACKAGE__->meta->make_immutable;

## Configure

sub args_spec {
	return (
		help => {
			cli  => 'help|?',
		},
	);
}

sub BUILD {
	my $self = shift;

	foreach my $subclass (qw(term view model)) {
		# Extract out subclass args from args
		my %args = (
			map { my $key = $_; /^_${subclass}_(.+)/; +($1 => delete $self->args->{$key}) }
			grep { /^_${subclass}_/ }
			keys %{ $self->args }
		);

		my $subclass_name = $self->args->{"${subclass}_class"};

		eval "require $subclass_name";
		die $@ if $@;

		if ($subclass eq 'view') {
			# We don't have one view per class; we create it per statement
			$self->args->{view_args} = \%args;
		}
		else {
			$self->{$subclass} = $subclass_name->new({
				app => $self,
				%args,
			});
		}
	}

	$self->model->db_connect();
}

sub parse_cli_args {
	my ($class, $argv, %args) = @_;
	my @argv = defined $argv ? @$argv : ();

	# Read in the args_spec() from each subclass we'll be using
	my %opts_spec;
	$args{term_class} ||= $_default_classes{term};
	$args{view_class} ||= $_default_classes{view};
	$args{model_class} ||= $_default_classes{model};

	foreach my $args_class ('main', 'view', 'term', 'model') {
		if ($args_class eq 'main') {
			my %args_spec = $class->args_spec();
			foreach my $arg (keys %args_spec) {
				next unless $args_spec{$arg}{cli};
				$opts_spec{ $args_spec{$arg}{cli} } = \$args{$arg};
			}
		}
		else {
			my $args_classname = $args{"${args_class}_class"};
			eval "require $args_classname";
			die $@ if $@;
			my %args_spec = $args_classname->args_spec();
			foreach my $key (keys %args_spec) {
				next unless $args_spec{$key}{cli};
				$opts_spec{ $args_spec{$key}{cli} } = \$args{"_${args_class}_$key"};
				if (my $default = $args_spec{$key}{default}) {
					$args{"_${args_class}_$key"} = $default;
				}
			}
		}
	}

	# Password is a special case
	foreach my $i (0..$#argv) {
		my $arg = $argv[$i];
		next unless $arg =~ m{^(?:-p|--password=)(.*)$};
		splice @argv, $i, 1;
		if (length $1) {
			$args{_model_password} = $1;
			# Remove the password from the program name so people can't see it in process listings
			$0 = join ' ', $0, @argv;
		}
		else {
			# Prompt the user for the password
			require Term::ReadKey;
			Term::ReadKey::ReadMode('noecho');
			print "Enter password: ";
			$args{_model_password} = Term::ReadKey::ReadLine(0);
			Term::ReadKey::ReadMode('normal');
			print "\n";
			chomp $args{_model_password};
		}
		last; # I've found what I was looking for
	}

	GetOptionsFromArray(\@argv, %opts_spec);

	# Database is a special case; if left over arguments, that's the database name
	if (@argv && int @argv == 1) {
		$args{_model_database} = $argv[0];
	}

	return \%args;
}

sub resolve_namespace_config_value {
	my ($self, $namespace, $key_or_keys, $default_config) = @_;

	# FIXME!!!  Why the hell is Perl letting me do this?  I thought Moose was always use strict / warnings
	$undeclared_variable = 1;

	my $return;
	my $cache_key = join ':', $namespace, ref $key_or_keys ? @$key_or_keys : $key_or_keys;
	if (exists $self->{_resolve_namespace_config_value_cache}{$cache_key}) {
		return $self->{_resolve_namespace_config_value_cache}{$cache_key};
	}

	if (ref $key_or_keys && int @$key_or_keys > 1) {
		my @keys = @$key_or_keys;
		my $first_key = shift @keys;
		my $default_hash = $default_config->{$first_key};
		my $defined_hash = $self->get_namespace_config_value($namespace, $first_key) || {};
		my $config = union([ $default_hash, $defined_hash ]);
		$return = _find_hash_value($config, @keys);
	}
	else {
		my $default = $default_config->{$key_or_keys};
		my $defined = $self->get_namespace_config_value($namespace, $key_or_keys) || undef;
		$return = defined $defined ? $defined : $default;
	}

	$self->{_resolve_namespace_config_value_cache}{$cache_key} = $return;
	return $return;
}

sub _find_hash_value {
	my ($config, @keys) = @_;
	my $key = shift @keys;
	return undef if ! defined $key;
	return undef if ! exists $config->{$key};
	my $value = $config->{$key};
	if (ref $value && ref $value eq 'HASH') {
		return _find_hash_value($value, @keys);
	}
	return $value;
}

sub get_namespace_config_value {
	my ($self, $namespace, $key) = @_;
	my $config = $self->config->{$namespace};
	return unless defined $config;
	return $config->{$key};
}

sub read_config_file {
	my $class = shift;

	# Read system settings first, then get more specific
	my @configs;
	my $configs = Config::Any->load_stems({ stems => \@_config_stems, use_ext => 1 });
	foreach my $config (@$configs) {
		my ($filename) = keys %$config;
		push @configs, $config->{$filename};
	}

	# Merge all the hash configs together smartly
	return union(\@configs);
}

sub new_from_cli {
	my $class = shift;
	my $args = $class->parse_cli_args(\@ARGV);
	if ($args->{help}) {
		print "TODO from spec!\n";
		exit;
	}
	my $config = $class->read_config_file();
	return $class->new(args => $args, config => $config);
}

## Main

sub run {
	my $self = shift;

	$self->log_info("Starting ".__PACKAGE__);

	my $input;
	while (defined ($input = $self->term->readline())) {
		$self->handle_term_input($input);
	}
}

sub shutdown {
	my $self = shift;

	$self->term->write_history();

	exit;
}

## Input handlers

sub handle_term_input {
	my ($self, $input) = @_;

	# Next if Ctrl-C or if user typed nothing
	if (! length $input) {
		return;
	}

	$input =~ s/\s*$//; # no trailing spaces
	$input =~ s/;*$//;  # no trailing semicolon

	# Extract out \G
	my %render_opts;
	if ($input =~ s/\\G$//) {
		$render_opts{one_row_per_column} = 1;
	}

	# Allow the user to pass non-SQL control verbs
	if ($input =~ m/^\s*(quit|exit)\s*$/) {
		$self->shutdown();
	}

	# Allow the user to execute perl code via '% print Dumper(...);'
	if (my ($perl_code) = $input =~ m/^% (.+)$/) {
		eval $perl_code;
		if ($@) {
			$self->log_error($@);
		}
		return;
	}

	if (my ($command) = $input =~ m/^\.([a-z]+)\b/i) {
		my $handled = $self->call_command(lc($command), $input);
		return if $handled;
	}

	$self->model->handle_sql_input($input, \%render_opts);
}

sub call_command {
	my ($command, $input) = @_;
	# Do nothing here; placeholder for plugin's to attach to
	return;
}

## Output display

sub create_view {
	my ($self, %args) = @_;

	my $view = $self->args->{view_class}->new(
		app => $self,
		%args,
		%{ $self->args->{view_args} },
	);

	if (my $plugins = $self->config->{view_plugins}) {
		$view->load_plugin($_) foreach @$plugins;
	}

	return $view;
}

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
