package App::AltSQL::Plugin::Out::Format::sql;

use Moose::Role;

sub format {
    my ($self, $header, $result) = @_;

    return if !$result || !@$result;

    if (!@$header) {
        @$header = sort keys %{ $result->[0] };
    }
    
    # todo: add support for non multi column insert for sqlite3
    my $sql =  'INSERT INTO table (' . join( ',', map{ escape($_, 'column') } @$header ) . ') VALUES';
    for my $row (@$result) {
        $sql .=  '(' . join( ',', map {escape($row->{$_})} @$header ) . '),';
    }

    chop($sql); # trailing ,

    return $sql;
}

sub escape {
    my ($value, $type) = @_;

    return 'NULL' if !defined $value;

    if (!$type || $type ne 'column') {
        $value =~ s/'/''/g;
        return "'$value'";
    }

    return "`$value`";
}

1;
