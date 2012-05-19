package App::AltSQL::Plugin::Dump::Format::csv;

use Moose::Role;

sub format {
    my ($self, $header, $result) = @_;

    return if !$result || !@$result;

    if (!@$header) {
        @$header = sort keys %{ $result->[0] };
    }

    my $csv = join( ",", map{ '"' . escape($_) . '"' } @$header ) . "\n";

    for my $row (@$result) {
        $csv .= join( ",", map{ '"' . escape($row->{$_}) . '"' } @$header ) . "\n";
    }

    return $csv;
}

sub escape {
    my ($value) = @_;
    return '' if !defined $value;
    $value =~ s/"/""/g;
    return $value;
}

1;
