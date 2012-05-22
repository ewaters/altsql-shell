package App::AltSQL::Plugin::Dump::Format;

use Moose;

sub _convert_to_array_of_hashes {
    my ($self, $table_data) = @_;

    my @new_array;

    my $cols = $table_data->{columns};

    for my $row ( @{ $table_data->{rows} } ) {
        my $hash;
        for my $i ( 0..(@$row - 1) ) {
            $hash->{ $cols->[$i]->{name} } = $row->[$i];
        }
        push @new_array, $hash;
    }

    return \@new_array;
}

1;
