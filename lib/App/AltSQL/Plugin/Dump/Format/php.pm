package App::AltSQL::Plugin::Dump::Format::php;

use Moose::Role;

sub format {
    my ($self, $header, $result) = @_;

    return if !$result || !@$result;

    if (!@$header) {
        @$header = sort keys %{ $result->[0] };
    }
    
    # todo: add support for non multi column insert for sqlite3
    my $sql =  'array(' . join( ',', map{ escape($_, 'column') } @$header ) . ') values';
    for my $row (@$result) {
        $sql .=  '(' . join( ',', map {escape($row->{$_})} @$header ) . '),';
    }

    chop($sql); # trailing ,

    return $sql;
}

sub escape {
    my ($value, $type) = @_;

    return '' if !defined $value;

    $value =~ s/"/\\"/g;

    return '"' . $value . '"';
}

1;
