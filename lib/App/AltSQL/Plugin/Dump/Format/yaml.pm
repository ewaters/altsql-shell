package App::AltSQL::Plugin::Dump::Format::yaml;

use Moose::Role;
use YAML qw(Dump);

sub format {
    my ($self, $header, $result) = @_;
    return Dump($result);
}

1;
