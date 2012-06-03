package My::ModifierResub;

use Moose;
use base qw(Exporter);

our @EXPORT = qw(modifier_resub %modifiers setup_method_modifiers);

# Arguments to new()
has skip_orig => ( is => 'ro' );
has return_value => ( is => 'ro' );

has called => ( is => 'rw' );
has args   => ( is => 'rw', default => sub { [] } );
has last_args => ( is => 'rw', default => sub { [] });

# Define hash that'll be used for local overrides
our %modifiers;

sub code {
	my $self = shift;
	return sub {
		my ($return, @args) = @_;
		$self->called(1);

		# Store the args
		push @{ $self->args }, \@args;
		$self->last_args(\@args);

		# If the caller wants a special return value, mixin the arrayref into $return
		if ($self->return_value) {
			$return->[$_] = $self->return_value->[$_] foreach 0..$#{ $self->return_value };
		}

		# On a 'before' call, returning true will skip the call of $orig
		return $self->skip_orig ? 1 : 0;
	};
}

sub modifier_resub (@) {
	return __PACKAGE__->new(@_);
}

sub setup_method_modifiers ($;$) {
	my ($name, $data) = @_;
	foreach my $method (@{ $data->{methods} }) {
		# Setup default, no-op sub refs
		$modifiers{"$name $method before"} ||= sub {};
		$modifiers{"$name $method after"} ||= sub {};

		my $meta_role = Moose::Meta::Role->create_anon_role();
		$meta_role->add_around_method_modifier($method => sub {
			my ($orig, $self, @args) = (shift, shift, @_);

			# Try the 'before' modifier and return @return if it returns true
			my @return;
			if ($modifiers{"$name $method before"}(\@return, @args)) {
				return wantarray ? @return : $return[0];
			}

			# Call original function
			@return = wantarray ? ($self->$orig(@args)) : (scalar $self->$orig(@args));

			$modifiers{"$name $method after"}(\@return);

			return wantarray ? @return : $return[0];
		});
		$meta_role->apply($data->{instance});
	}
}

1;
