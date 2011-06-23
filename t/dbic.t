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

my $ev1 = $schema->resultset('Raw')->find(1);
diag Dumper({ $ev1->get_columns });
