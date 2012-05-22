package App::AltSQL::Plugin::Dump::Format::yaml;

use Moose::Role;
use YAML qw(Dump);

sub format {
    my ($self, %params) = @_;
    my $data = $self->_convert_to_array_of_hashes($params{table_data});
    return Dump($data);
}

1;
