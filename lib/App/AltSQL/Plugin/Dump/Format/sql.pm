package App::AltSQL::Plugin::Dump::Format::sql;

use Moose::Role;

sub format {
    my ($self, %params) = @_;

    my $table_data = $params{table_data};

    # todo: add a create table once we have the datatypes in table data

    # todo: add support for non multi column insert for sqlite3
    my $sql =  'INSERT INTO table (' .
        join( ',', map{ escape($_->{name}, 'column') } @{ $table_data->{columns} } ) . ') VALUES';

    for my $row (@{ $table_data->{rows} }) {
        $sql .=  '(' . join( ',', map {escape($_)} @$row ) . '),';
    }

    # change last trailing comma with semicolon
    $sql =~ s/,$/;/;

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
