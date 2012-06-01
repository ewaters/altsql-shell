package App::AltSQL::Plugin::Dump;

use Moose::Role;
use Moose::Util qw( apply_all_roles );

use App::AltSQL::Plugin::Dump::Format;

=head1 Name

Dump AltSQL Plugin

=head1 Synopsis

Usage:

 .dump <file>.[csv|html|json|pl|pm|sql|xls|xml|yaml|yml] <query>;

=head1 Description

This plugin will allow you to dump out results from
a sql query into one of many data formats.

=head1 Examples

Given:

 CREATE TABLE `users` (
   `id` int(11) NOT NULL AUTO_INCREMENT,
   `name` varchar(32) NOT NULL,
   PRIMARY KEY (`id`)
 );

CSV:

 .dump out.csv select * from users;

out.csv:

 "id","name"
 "1","Moo"
 "2","Pie"
 "3","Cow"

HTML:

 .dump out.html select * from users;

out.html:

=begin html

<style>table{margin: 1em 1em 1em 2em;background: whitesmoke;border-collapse: collapse;}table th, table td{border: 1px gainsboro solid;padding: 0.2em;}table th{background: gainsboro;text-align: left;}</style><table><tr><th>id</th><th>name</th></tr><tr><td>1</td><td>Moo</td></tr><tr><td>2</td><td>Pie</td></tr><tr><td>3</td><td>Cow</td></tr></table>

=end html

JSON:

 .dump out.json select * from users;

out.json:

 [{"name":"Moo","id":"1"},{"name":"Pie","id":"2"},{"name":"Cow","id":"3"}]

PERL:

 .dump out.[pl|pm] select * from users;

out.[pl|pm]:

 $VAR1 = [
   {
     'id' => '1',
     'name' => 'Moo'
   },
   {
     'id' => '2',
     'name' => 'Pie'
   },
   {
     'id' => '3',
     'name' => 'Cow'
   },
 ];

SQL:

 .dump out.sql select * from users;

out.sql:

 INSERT INTO table (`id`,`name`) VALUES('1','Moo'),('2','Pie'),('3','Cow');

XLS:

 .dump out.xls select * from users;

out.xls:

 You just get a excel spreadsheet...

XML:

 .dump out.xml select * from users;

out.xml:

 <table>
   <row>
     <field name="id">1</field>
     <field name="name">Moo</field>
   </row>
   <row>
     <field name="id">2</field>
     <field name="name">Pie</field>
   </row>
   <row>
     <field name="id">3</field>
     <field name="name">Cow</field>
   </row>
 </table>

YAML:

 .dump out.[yaml|yml] select * from users;

out.[yaml|yml]:

 ---
 - id: 1
   name: Moo
 - id: 2
   name: Pie
 - id: 3
   name: Cow

=cut

around call_command => sub {
    my ($orig, $self, @args) = @_;

    my $option;

    my ($command, $input) = @args[0..1];

    if ($command ne 'dump') {
        # Call next chained command
        return $self->$orig(@args);
    }

    my (undef, $filename, $query) = split /\s+/, $input, 3;

    if (!$filename || !$query) {
        $self->log_error("Usage: .dump \$filename \$sql");
        $self->log_error("Available formats: csv, xls, html, json, [pl|pm], sql, xml, [yml|yaml]");

        return 1; # handled, won't run this as a query
    }

    my ($ext) = $filename =~ /\.([a-zA-Z-]+)$/;

    my $format;

    if    ($ext =~ /^pl|pm$/i)    { $format = 'perl';  }
    elsif ($ext =~ /^yml|yaml$/i) { $format = 'yaml';  }
    else                          { $format = lc $ext; }

    my $formatter = App::AltSQL::Plugin::Dump::Format->new();

    local $@;

    eval {
        apply_all_roles( $formatter, "App::AltSQL::Plugin::Dump::Format::$format" );
    };

    if ($@) {
        $self->log_error("Sorry $format is not a supported format because:\n$@");
        return 1;
    }

    my $sth = $self->model->execute_sql($query);
	return 1 unless $sth; # handled; error occurred has has been reported to user

    my @headers;

    my %table_data;

    if ( $sth->{NUM_OF_FIELDS} ) {
        for my $i (0 .. $sth->{NUM_OF_FIELDS} - 1) {
            push @{ $table_data{columns} }, { name => $sth->{NAME}[$i] };
        }
    }

    $table_data{rows} = $sth->fetchall_arrayref() || [];

    if ( @{ $table_data{rows} } ) {
        my $data = $formatter->format(
            table_data => \%table_data,
            filename   => $filename,
        );
        if ($data) {
            open(my $FILE, '>', $filename);
            print $FILE $data;
            close($FILE);
        }
    }

	$self->log_info("Wrote ".($sth->{NUM_OF_FIELDS} || 0)." rows to file $filename");

    return 1;
};

1;
