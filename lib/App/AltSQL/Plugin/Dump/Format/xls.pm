package App::AltSQL::Plugin::Dump::Format::xls;

use Moose::Role;
use Spreadsheet::WriteExcel::Big;

sub format {
    my ($self, $header, $result, $filename) = @_;

    return if !$result || !@$result;

    if (!@$header) {
        @$header = sort keys %{ $result->[0] };
    }

    my $workbook  = Spreadsheet::WriteExcel::Big->new($filename);
    my $worksheet = $workbook->add_worksheet();

    my $header_format = $workbook->add_format;
    $header_format->set_bold;

    my $col_pos = 0;
    my $row_pos = 0;

    # write header
    for my $head (@$header) {
        $worksheet->write(0, $col_pos++, $head, $header_format);
    }

    # move down 2 lines, let it breath some
    $row_pos += 2;

    for my $row (@$result) {
        $col_pos = 0; # reset col_pos.
        for my $data (map{ $row->{$_} } @$header) {
            $worksheet->write($row_pos, $col_pos++, $data);
        }
        $row_pos++;
    }

    $workbook->close();

    return;
}

1;
