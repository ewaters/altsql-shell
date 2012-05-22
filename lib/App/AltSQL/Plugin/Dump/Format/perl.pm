package App::AltSQL::Plugin::Dump::Format::perl;

use Moose::Role;
use Data::Dumper;

sub format {
    my ($self, %params) = @_;

    $Data::Dumper::Sortkeys = 1;

    my $data = $self->_convert_to_array_of_hashes($params{table_data});

    return Dumper($data);
}

1;
