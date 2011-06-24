# another play with Harold, using DBIC

use Test::More;
use Test::Moose;

use FindBin '$Bin';
use lib "$Bin/../lib";

use Harold::Schema;
use Harold::Queue::DBIC;
use Data::Dumper;

my $schema = Harold::Schema->connect("dbi:SQLite:$Bin/my.db");
$schema->deploy({ add_drop_table => 1 });

my $conn = Harold::Connection::DBIC->new(
    dbic => $schema,
);

isa_ok  $conn, 'Harold::Connection::DBIC';
does_ok $conn, 'Harold::Connection';

my $raw = $conn->createQ( name  => 'raw', tablesource => 'Raw' );

isa_ok $raw, 'Harold::Queue';

$raw->push({ 
    event_type => 'login',
    user       => 'fred',
    status     => 'ok',
});

my $ev1 = $schema->resultset('Raw')->search(
    { event_created => {
        '<', \"datetime('now', '+1 minute')",
        '>', \"datetime('now', '-1 minute')",
      }})->first;

ok $ev1, "Got a result";
is $ev1->id,   1,       'id';
is $ev1->event_type, 'login', 'event_type';
is_deeply $ev1->json, 
    {status =>"ok",queue_id=>1,user=>"fred"}, 
    'json inflated';

my $copied = $raw->copy('copy');
diag Dumper( $copied->toArray );

done_testing;
