package App::AltSQL::Plugin::Dump::Format::csv;

use Moose::Role;

sub format {
    my ($self, %params) = @_;

    my $table_data = $params{table_data};

    # make headers for the csv file
    my $csv = join( ",", map{ escape($_->{name}) } @{ $table_data->{columns} } ) . "\n";

    # print out the rows
    for my $row (@{ $table_data->{rows} }) {
        $csv .= join( ",", map{ escape($_) } @$row ) . "\n";
    }

    return $csv;
}

sub escape {
    my ($value) = @_;
    return '' if !defined $value;
    $value =~ s/"/""/g;
    return '"' . $value . '"';
}

1;
