package App::AltSQL::Plugin::Dump::Format::html;

use Moose::Role;

sub format {
    my ($self, $header, $result) = @_;

    return if !$result || !@$result;

    if (!@$header) {
        @$header = sort keys %{ $result->[0] };
    }

    # ehhh prob shouldn't put this here but couldn't resist.
    my $css =
        '<style>table{margin: 1em 1em 1em 2em;background: whitesmoke;border-collapse: collapse;}
         table th, table td{border: 1px gainsboro solid;padding: 0.2em;}
         table th{background: gainsboro;text-align: left;}</style>';

    my $html  = qq|<html><head><style>$css</style></head><body><table>|;
       $html .= '<tr>' . join( '', map{'<th>' . escape($_) . '</th>' } @$header ) . '</tr>';

    for my $row (@$result) {
        $html .=  '<tr>' . join( '', map {'<td>' . escape($row->{$_}) . '</td>' } @$header ) . '</tr>';
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
