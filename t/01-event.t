use Test::More;
use Harold::Event;
use Data::Dumper;

my $events = Harold::Event->new;

my $event = $events->raise( Base =>
    text => 'Testing events',
);

isa_ok $event, 'Harold::Event::Base';

my $dt = $event->datestamp;
my $xml = $event->xml_atom_entry->as_xml;
is $xml, <<XML, 'Render to XML::Atom::Entry' or diag $xml;
<?xml version="1.0" encoding="utf-8"?>
<entry xmlns="http://purl.org/atom/ns#">
  <title>Testing events</title>
  <content mode="xml">
    <div xmlns="http://www.w3.org/1999/xhtml">Testing events
$dt</div>
  </content>
</entry>
XML

done_testing();
