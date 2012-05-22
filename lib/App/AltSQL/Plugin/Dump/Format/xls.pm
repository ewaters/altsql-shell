package App::AltSQL::Plugin::Dump::Format::xls;

use Moose::Role;
use Spreadsheet::WriteExcel::Big;

sub format {
    my ($self, %params) = @_;

    my $filename   = $params{filename};
    my $table_data = $params{table_data}; 

    my $workbook  = Spreadsheet::WriteExcel::Big->new($filename);
    my $worksheet = $workbook->add_worksheet();

    my $header_format = $workbook->add_format;
    $header_format->set_bold;

    my $col_pos = 0;
    my $row_pos = 0;

    # write header
    for my $column ( @{ $table_data->{columns} } ) {
        $worksheet->write(0, $col_pos++, $column->{name}, $header_format);
    }

    # move down 2 lines, let it breath some
    $row_pos += 2;

    for my $row ( @{ $table_data->{rows} } ) {
        $col_pos = 0; # reset col_pos.
        $worksheet->write($row_pos, $col_pos++, $_) for @$row;
        $row_pos++;
    }

    $workbook->close();

    return;
}

1;
