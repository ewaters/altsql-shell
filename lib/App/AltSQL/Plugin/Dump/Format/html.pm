package App::AltSQL::Plugin::Dump::Format::html;

use Moose::Role;

sub format {
    my ($self, %params) = @_;

    my $table_data = $params{table_data};

    # ehhh prob shouldn't put this here but couldn't resist.
    my $css = '<style>table{margin: 1em 1em 1em 2em;background: whitesmoke;border-collapse: collapse;}table th, table td{border: 1px gainsboro solid;padding: 0.2em;}table th{background: gainsboro;text-align: left;}</style>';

    my $html  = "<html><head><style>$css</style></head><body><table>";
       $html .= '<tr>' . join( '', map{ '<th>' . escape($_->{name}) . '</th>' } @{ $table_data->{columns} } ) . "</tr>";

    for my $row (@{ $table_data->{rows} }) {
        $html .=  '<tr>' . join( '', map {'<td>' . escape($_) . '</td>' } @$row ) . '</tr>';
    }

    $html .= '</table>';

    return $html;
}

sub escape {
    my ($value) = @_;
    return '' if !defined $value;
    $value =~ s/</&lt/g;
    $value =~ s/>/&gt/g;
    return $value;
}

1;
