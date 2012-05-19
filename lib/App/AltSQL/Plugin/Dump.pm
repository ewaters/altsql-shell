package App::AltSQL::Plugin::Dump;

use Moose::Role;
use Moose::Util qw( apply_all_roles );

use App::AltSQL::Plugin::Dump::Format;

=head1 Dump

The SQL:

  .dump csv filename.csv SELECT * from orders;

Will:

  * Create filename.csv
  * Populate the file with the result

Other formats:

  .dump json filename.json SELECT * from orders;
  .dump html filename.html SELECT * from orders;
  .dump sql filename.sql SELECT * from orders;
  .dump xml filename.sql SELECT * from orders;
  .dump xml-a filename.sql SELECT * from orders;

=cut

around call_command => sub {
    my ($orig, $self, @args) = @_;

    my $option;

    my ($command, $input) = @args[0..1];

    if ($command ne 'dump') {
        # Call next chained command
        return $self->orig(@args);
    }

    my ($filename, $query) = $input =~ m{^\.dump\s*([^\s]+)\s*(.*?)$};

    if (!$filename) {
        $self->log_error("Usage: .dump \$filename \$sql");
        $self->log_error("Available formats: csv, xls, html, json, [pl|pm], php, sql, [xml|xml-a], [yml|yaml]");

        return 1; # handled, won't run this as a query
    }

    my ($ext) = $filename =~ /\.([a-zA-Z-]+)$/;

    my $format;

    if    ($ext =~ /^pl|pm$/i)    { $format = 'perl';  }
    elsif ($ext =~ /^yml|yaml$/i) { $format = 'yaml';  }
    else                          { $format = lc $ext; }

    # todo: really hate the way i did  this, fix later.
    if ($format =~ /-/) {
        # we pass everything to the right of - as params yuk
        ($format, $option) = split(/-/,$format);
    }

    my $formatter = App::AltSQL::Plugin::Dump::Format->new();

    local $@;

    eval {
        apply_all_roles( $formatter, "App::AltSQL::Plugin::Dump::Format::$format" );
    };

    if ($@) {
        $self->log_error("Sorry $format is not a supported format.");
        return 1;
    }

    my $sth = $self->model->dbh->prepare($query);
    $sth->execute();

    my @headers;
    if ( $sth->{NUM_OF_FIELDS} ) {
        for my $i (0 .. $sth->{NUM_OF_FIELDS} - 1) {
            push @headers, $sth->{NAME}[$i];
        }
    }

    my $result = $sth->fetchall_arrayref({});
    my $data = $formatter->format( \@headers, $result, $filename, $option );

    if ($data) {
        open(FILE, '>', $filename);
        print FILE $data;
        close(FILE);
    }

    return 1;
};

1;
