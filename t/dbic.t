# another play with Harold, using DBIC

use FindBin '$Bin';
use lib "$Bin/../lib";

use Harold::Schema;
use Harold::Queue::DBIC;
use Data::Dumper;

my $schema = Harold::Schema->connect("dbi:SQLite:$Bin/my.db");
$schema->deploy({ add_drop_table => 1 });

