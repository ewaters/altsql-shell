use strict;
use warnings;
use Test::More;
use Term::ANSIColor;

BEGIN {
	use_ok 'App::AltSQL';
	use_ok 'App::AltSQL::Term';
	use_ok 'App::AltSQL::Model::MySQL';
}

## Setup

my $app = bless {}, 'App::AltSQL';

my $model = App::AltSQL::Model::MySQL->new(
	app      => $app,
	host     => 'localhost',
	user     => 'testuser',
);
$app->{model} = $model;

my $term = App::AltSQL::Term->new(
	app => $app,
);
$app->{term} = $term;

#$model->setup();
#$term->setup();

## Testing

$term->prompt('myprompt> ');
is $term->render_prompt(), 'myprompt> ', "Basic, non-special prompt";

$term->prompt('myprompt%%> ');
is $term->render_prompt(), 'myprompt%> ', "Escaped percent sign";

$term->prompt('%u@%h> ');
is $term->render_prompt(), 'testuser@localhost> ', "Some substitutions";

$term->prompt('(%u@%h) [%d]> ');
is $term->render_prompt(), '(testuser@localhost) [(none)]> ', "Issue #28, without database"; 

$model->current_database('saklia');

$term->prompt('(%u@%h) [%d]> ');
is $term->render_prompt(), '(testuser@localhost) [saklia]> ', "Issue #28, with database"; 

## Perl eval

$term->prompt('%e{ ++( $self->{_statement_counter} ) }> ');
is $term->render_prompt(), '1> ', "Arbitrary perl";
is $term->render_prompt(), '2> ', "Arbitrary perl, part two";

$term->prompt('%e{ missing end brace');
is $term->render_prompt(), '', "Missing end brace";

$term->prompt('%e{ invalid perl code }');
is $term->render_prompt(), 'err', "Invalid perl code";

## Color

$term->prompt('%c{bold}%u%c{reset}%c{bold red}@%h%c{reset}> ');
is $term->render_prompt(),
	colored('testuser', 'bold') . colored('@localhost', 'bold red') . '> ',
	"Colored prompt";

## MySQL .my.cnf format

$model->{prompt} = '\\\\u@\\\\h[\\\\d]\\\\_';
is $model->parse_prompt(), '%u@%h[%d] ', "MySQL-style prompt converted into local style";

$model->{prompt} = '(\\\\u@\\\\h) [\\\\d]>\\\\_';
$term->prompt( $model->parse_prompt );
is $term->render_prompt(), '(testuser@localhost) [saklia]> ', "Issue #28 from .my.cnf";

## DateTime testing

eval { require DateTime; };
if ($@) {
	print STDERR "Can't continue testing without DateTime\n";
	done_testing;
}

my $now = DateTime->now();

$term->prompt('%u@%h[%t{%H:%M:%S}]> ');
is $term->render_prompt($now), 'testuser@localhost['.$now->strftime('%H:%M:%S').']> ', "Simple DateTime substitution";

done_testing;
