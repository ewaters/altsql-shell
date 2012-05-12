package App::AltSQL::Model;

use Moose;

with 'App::AltSQL::Role';
with 'MooseX::Object::Pluggable';

no Moose;
__PACKAGE__->meta->make_immutable();

1;
