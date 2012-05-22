package App::AltSQL::Plugin::Dump::Format::json;

use Moose::Role;
use JSON;

sub format {
    my ($self, %params) = @_;
    my $data = $self->_convert_to_array_of_hashes($params{table_data});
    return JSON->new->encode($data);
}

1;
