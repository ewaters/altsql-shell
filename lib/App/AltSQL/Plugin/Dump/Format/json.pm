package App::AltSQL::Plugin::Dump::Format::json;

use Moose::Role;
use JSON::XS;

sub format {
    my ($self, $header, $result) = @_;
    return JSON::XS->new->encode($result);
}

1;
