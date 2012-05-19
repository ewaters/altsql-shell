package App::AltSQL::Plugin::Dump::Format::xml;

use Moose::Role;
use XML::Simple;

sub format {
    my ($self, $header, $result, $filename, $option) = @_;

    return if !$result || !@$result;

    if (!@$header) {
        @$header = sort keys %{ $result->[0] };
    }

    my @node_result;

    # defualt behavior is to show xml nodes for your row.
    # a means it will show them as attributes ( ex: <anon id="1" name="joe" sex="male" />
    if ($option && $option eq 'a') {
        return XMLout( $result );
    } else {
        for my $row (@$result) {
            my $new_row;
            $new_row->{$_} = [ $row->{$_} ] for (sort keys %$row);


            push @node_result, $new_row;
        }
        return XMLout( \@node_result );
    }
}

1;
