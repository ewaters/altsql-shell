use strict;
use warnings;
use Test::More;
use Test::Deep;
use App::AltSQL::Model;

ok my $model = App::AltSQL::Model->new(app => 1);

is $model->is_end_of_statement('test'), 0, 'Incomplete statement';

is $model->is_end_of_statement('test;'), 1, 'Semicolon completes statement';

is $model->is_end_of_statement('quit'), 1, 'quit statement';

is $model->is_end_of_statement('exit'), 1, 'exit statement';

is $model->is_end_of_statement('   '), 1, 'blank space statement';

is $model->is_end_of_statement('test\G'), 1, '\G statement';

is $model->is_end_of_statement('test\c'), 1, '\c statement';

is $model->is_end_of_statement('select * from film where title = ";'), 0, 'Semi colon in string';
is $model->is_end_of_statement(qq{select * from film where title = ";\n";}), 1, 'Tail end of statement where we were in a string';

is $model->is_end_of_statement('insert into mytab values (";",'), 0, 'Incomplete statement';

is $model->is_end_of_statement(q{select * from film where title = '\';}), 0, 'Semi colon in string';

is $model->is_end_of_statement(q{select * from film where title = "\";}), 0, 'Semi colon in string';

is $model->is_end_of_statement(q{select * from film where title = "\\\\";}), 1, 'Escaped slash, terminated string and end of statement';

is $model->is_end_of_statement(q{select * from film where title = /* "\";}), 0, 'Semi colon in comment';
is $model->is_end_of_statement(qq{select * from film where title = /* "\";\n*/ 'test';}), 1, 'Statement terminated after comment closes';

is $model->is_end_of_statement(q{select 'test'; -- a simple statement}), 1, 'Statement terminated Got a comment after';

done_testing;
