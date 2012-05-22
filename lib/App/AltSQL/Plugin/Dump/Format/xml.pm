package App::AltSQL::Plugin::Dump::Format::xml;

use Moose::Role;
use XML::Simple;

sub format {
    my ($self, %params) = @_;

    my @xml;

    my $table_data = $params{table_data};
    my $col = $table_data->{columns};

    for my $row ( @{ $table_data->{rows} } ) {
        my $new_row;
        for my $i ( 0..(@$row - 1) ) {
            my $name = $col->[$i]->{name};
            push @{ $new_row->{field} }, { name => $name, content => $row->[$i] };
        }
        push @xml, $new_row;
    }

    return XMLout( { row => \@xml }, RootName => 'table', );
}

1;
