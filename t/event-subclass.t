use Test::More;
use lib 't/lib';
use Foo::Event;
use Data::Dumper;

my $events = Foo::Event->new;

my $event = $events->raise( Bar =>
    text => 'Testing events',
);

isa_ok $event, 'Harold::Event::Base';
isa_ok $event, 'Foo::Event::Bar';

my $xml = $event->xml_atom_entry->as_xml;
is $xml, <<XML, 'Render to XML::Atom::Entry' or diag $xml;
<?xml version="1.0" encoding="utf-8"?>
<entry xmlns="http://purl.org/atom/ns#">
  <title>Testing events</title>
  <content mode="xml">
    <div xmlns="http://www.w3.org/1999/xhtml">RARR Testing events</div>
  </content>
</entry>
XML

done_testing();
