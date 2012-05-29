package App::AltSQL;

=encoding utf-8

=head1 NAME

App::AltSQL - A drop in replacement to the MySQL prompt with a pluggable Perl interface

=head1 SYNOPSIS

  ./altsql -h <host> -u <username> -D <database> -p<password>

  altsql> select * from film limit 4;
  ╒═════════╤══════════════════╤════════════════════════════
  │ film_id │ title            │ description                
  ╞═════════╪══════════════════╪════════════════════════════
  │       1 │ ACADEMY DINOSAUR │ A Epic Drama of a Feminist 
  │       2 │ ACE GOLDFINGER   │ A Astounding Epistle of a D
  │       3 │ ADAPTATION HOLES │ A Astounding Reflection of 
  │       4 │ AFFAIR PREJUDICE │ A Fanciful Documentary of a
  ╘═════════╧══════════════════╧════════════════════════════
  4 rows in set (0.00 sec)

=head1 DESCRIPTION

AltSQL is a way to improve your user experience with C<mysql>, C<sqlite3>, C<psql> and other tools that Perl has L<DBI> drivers for.  Currently written for MySQL only, the long term goal of this project is to provide users of the various SQL-based databases with a familiar command line interface but with modern improvements such as color, unicode box tables, and tweaks to the user interface that are fast and easy to prototype and experiment with.

There are a few key issues that this programmer has had with using the mysql client every day.  After looking for alternatives and other ways to fix the problems, reimplementing the client in Perl seemed like the easiest approach, and lent towards the greatest possible adoption by my peers.  Here are a few of those issues:

=over 4

=item Ctrl-C kills the program

All of the shells that we used on a daily basis allow you to abandon the half-written statement on the prompt by typing Ctrl-C.  Spending all day in shells, you expect this behavior to be consistent, but you do this in mysql and you will be thrown to the street.  Let's do what I mean, and abandon the statement.

=item Wide output wraps

We are grateful that mysql at least uses ASCII art for table formatting (unlike C<sqlite3> for some reason).  But there are some tables that I work with that have many columns, with long names (it's often easier to keep adding columns to a table over time).  As a result, when you perform a simple `select * from fim limit 4` you quickly find your terminal overwhelmed by useless ASCII art attempting (and mostly failing) to provide any semblance of meaning from the result.  You can throw a '\G' onto the command, but if it took 10 seconds to execute and you locked tables while doing it, you could be slowing down your website or letting your slave fall behind on sync.

Suffice it to say, it's a much better experience if, just like with C<git diff>, wide output is left wide, and you are optionally able to scroll horizontally with your arrow keys like you wanted in the first place.

=item Color

Most other modern programs we developers use on a daily basis (vim, ls, top, git, tmux, screen) offer to provide additional context to you via color.  By consistently setting colors on a variable type or file type, programs can convey to us additional context that allows us to better grasp and understand what's happening.  They help us be smarter and faster at our jobs, and detect when we've made a mistake.  There's no reason we shouldn't use color to make it obvious which column(s) form the primary key of a table, or which columns are a number type or string type.  The DBI statement handler contains lots of context, and we can interrogate the C<information_schema> tables in mysql for even more.

=item Unicode Box characters

The usage of '|', '+' and '-' for drawing tables and formatting data seems a bit antiquated.  Other tools are adopting Unicode characters, and most programmers are now using terminal programs that support Unicode and UTF8 encoding natively.  The Unicode box symbol set allows seamless box drawing which allows you to read between the lines, so to speak.  It is less obtrusive, and combining this with color you can create a more useful and clear user experience.

=back

I've thought of a number of other features, but so too have my coworkers and friends.  Most people I've spoken with have ideas for future features.  Next time you're using your DB shell and find yourself irritated at a feature or bug in the software that you feel could be done much better, file a feature request or, better yet, write your own plugins.

=head1 CONFIGURATION

The command line arguments inform how to connect to the database, whereas the configuration file(s) provide behavior and features of the UI.

=head2 Command Line

The following options are available.

=over 4

=item -h HOSTNAME | --host HOSTNAME

=item -u USERNAME | --user USERNAME

=item -p | --password=PASSWORD | -pPASSWORD

=item --port PORT

=item -D DATABASE | --database DATABASE

Basic connection parameters to the MySQL database.

=item --A | --no-auto-rehash

By default, upon startup and whenever the database is changed, the C<information_schema> tables will be read to perform tab completion.  Disable this behavior to get a faster startup time (but no tab complete).

=back

=head2 Config File

We are using L<Config::Any> for finding and parsing the configuration file.  You may use any format you'd like to write it so long as it's support in C<Config::Any>.

=over 4

=item /etc/altsql.(yml|cnf|ini|js|pl)

=item ~/.altsql.(yml|cnf|ini|js|pl)

Write your configuration file to either the system or the local configuration locations.  The local file will inherit from the global configuration but with local modifications.  For purposes of this example I'll be writing out the config in YAML, but again any other compatible format would do just as well.

=back

  ---
  plugins:
    - Tail
    - Dump

  view_plugins:
    - Color
    - UnicodeBox

  App::AltSQL::View::Plugin::Color:
    header_text:
      default: red
    cell_text:
      is_null: blue
      is_primary_key: bold
      is_number: yellow

  App::AltSQL::View::Plugin::UnicodeBox:
    style: heavy_header
    split_lines: 1
    plain_ascii: 0
  
This is the default configuration, and currently encompasses all the configurable settings.  This should be future safe; as you can see, plugins may use this file for their own variables as there are namespaced sections.

=head1 EXTENDING

As mentioned above, one key point of this project is to make it easy for people to extend.  For this reason, I've built it on L<Moose> and offer a L<MooseX::Object::Pluggable> interface.  If you extend C<App::AltSQL>, you may want to know about the following methods.

=cut

use Moose;
use Getopt::Long qw(GetOptionsFromArray);
use Params::Validate;
use Data::Dumper;
use Config::Any;
use Hash::Union qw(union);

our $VERSION = 0.04;
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
my %default_config = (
	plugins => [ 'Tail', 'Dump' ],
	view_plugins => [ 'Color', 'UnicodeBox' ],
);

=head2 Accessors

=over 4

=item term - the singleton L<App::AltSQL::Term> (or subclass) instance

=item view - the class in which all table output will be accomplished (defaults to L<App::AltSQL::View>)

=item model - where the database calls happen (L<App::AltSQL::Model::MySQL>)

=cut

has ['term', 'view', 'model']  => (is => 'ro');

=item args

Hash of the command line arguments

=item config

Hash of the file configuration

=back

=cut

has ['args', 'config'] => (is => 'rw');

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

	# Call setup on each subclass now that they're all created
	foreach my $subclass (qw(term model)) {
		$self->{$subclass}->setup();
	}

	$self->model->db_connect();
}

=head2 parse_cli_args \@ARGV

Called in C<bin/altsql> to collect command line arguments and return a hashref

=cut

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

=head2 resolve_namespace_config_value $namespace, $key | [ $key1, $key2, ... ], \%default_config

  $self->resolve_namespace_config_value('MyApp', 'timeout', { timeout => 60 });
  # Will search $self->config->{MyApp}{timeout} and will return that or the default 60 if not present

Provides plugin authors with easy access to the configuration file.  Provide either an arrayref of keys for deep hash matching or a single key for a two dimensional hash.

=cut

sub resolve_namespace_config_value {
	my ($self, $namespace, $key_or_keys, $default_config) = @_;

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

=head2 get_namespace_config_value $namespace, $key

Return a config value of the given key in the namespace.  Returns empty list if non-existant.

=cut

sub get_namespace_config_value {
	my ($self, $namespace, $key) = @_;
	my $config = $self->config->{$namespace};
	return unless defined $config;
	return $config->{$key};
}

=head2 read_config_file

Will read in all the config file(s) and return the config they represent

=cut

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

=head2 new_from_cli

Called in C<altsql> to read in the command line arguments and create a new instance from them and any config files found.

=cut

sub new_from_cli {
	my $class = shift;
	my $args = $class->parse_cli_args(\@ARGV);
	if ($args->{help}) {
		print "TODO from spec!\n";
		exit;
	}
	my $config = $class->read_config_file();
	my $self = $class->new(args => $args, config => $config || \%default_config);

	# Load in any plugins that are configured
	foreach my $plugin (@{ $self->config->{plugins} }) {
		$self->load_plugin($plugin);
	}

	return $self;
}

=head2 run

Start the shell up and enter the readline event loop.

=cut

sub run {
	my $self = shift;

	$self->log_info("Starting ".__PACKAGE__);

	my $input;
	while (defined ($input = $self->term->readline())) {
		$self->handle_term_input($input);
	}
}

=head2 shutdown

Perform any cleanup steps here.

=cut

sub shutdown {
	my $self = shift;

	$self->term->write_history();

	exit;
}

=head2 handle_term_input $input

The user has just typed something and submitted the buffer.  Do something with it.  Most notably, parse it for directives and act upon them.

=cut

sub handle_term_input {
	my ($self, $input) = @_;

	# Next if Ctrl-C or if user typed nothing
	if (! length $input) {
		return;
	}

	$input =~ s/\s*$//; # no trailing spaces
	$input =~ s/;*$//;  # no trailing semicolon

	# Support mysql '\c' clear command
	if ($input =~ m/\\c$/) {
		return;
	}

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

=head2 call_command $command, $input

Currently, the application treats any text that starts with a period as a command to the program rather then as SQL to be sent to the server.  This method will be called with that command and the full line types.  So, if someone typed '.reset screen', command would be 'reset' and the input woudl be '.reset screen'.  This is naturally a good place to add any extensions to the SQL syntax.

=cut

sub call_command {
	my ($self, $command, $input) = @_;
	# Do nothing here; placeholder for plugin's to attach to
	return;
}

=head2 create_view %args

Call L<App::AltSQL::View> C<new()>, mixing in the app and command line view arguments and loading any requested plugins.

=cut

sub create_view {
	my ($self, %args) = @_;

	my $view = $self->args->{view_class}->new(
		app => $self,
		%args,
		%{ $self->args->{view_args} },
	);

	if (my $plugins = $self->config->{view_plugins}) {
		$view->load_plugins(@$plugins);
	}

	return $view;
}

=head2 log_info, log_debug, log_error

Your basic logging methods, they all currently do the same thing.

=cut

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

no Moose;
__PACKAGE__->meta->make_immutable;

=head1 DEVELOPMENT

This module is being developed via a git repository publicly available at http://github.com/ewaters/altsql-shell.  I encourage anyone who is interested to fork my code and contribute bug fixes or new features, or just have fun and be creative.

=head1 COPYRIGHT

Copyright (c) 2012 Eric Waters and Shutterstock Images (http://shutterstock.com).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
