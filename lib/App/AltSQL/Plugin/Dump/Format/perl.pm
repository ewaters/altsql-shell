package App::AltSQL::Plugin::Dump::Format::perl;

use Moose::Role;
use Data::Dumper;

sub format {
    my ($self, $header, $result) = @_;
    return Dumper($result);
}

1;
