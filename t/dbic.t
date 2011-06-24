# another play with Harold, using DBIC

use Test::More;
use Test::Moose;
use Test::Deep;

use FindBin '$Bin';
use lib "$Bin/../lib";

use Harold::Schema;
use Harold::Queue::DBIC;
use Data::Dumper;
local $Data::Dumper::Indent = 1;
local $Data::Dumper::Maxdepth = 4;

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

cmp_deeply [$copied->toArray],
    [{
        event_created => isa('DateTime'),
        event_type => 'login',
        user       => 'fred',
        status     => 'ok',
        from_id    => 1,
        id         => 1,
        queue_id   => 2,
    }], 
    'Copied data ok';

$raw->push({ 
    event_type => 'login',
    user       => 'bill',
    status     => 'fail',
});

my $mapped = $copied->map( mapped =>
    code => sub {
        my $hashref = shift;
        my $status = $hashref->{status} eq 'ok' ? 'YAY!' : 'FAIL!';
        return { 
            %$hashref, 
            status => $status,
        };
    });
# this should also bring mapped up to date.

cmp_deeply [$mapped->toArray],
    [{
        event_created => isa('DateTime'),
        event_type => 'login',
        user       => 'fred',
        status     => 'YAY!',
        from_id    => 1,
        id         => 3,
        queue_id   => 4,
    }, 
    {
        event_created => isa('DateTime'),
        event_type => 'login',
        user       => 'bill',
        status     => 'FAIL!',
        from_id    => 2,
        id         => 4,
        queue_id   => 4,
    }], 
    'mapping ok'
    or diag Dumper([$mapped->toArray]);;

$raw->push({ 
    event_type => 'email',
    user       => 'pratesh',
    status     => 'ok',
});

my $filtered = $mapped->filter( filtered =>
    code => sub {
        $_[0]->{status} eq 'YAY!',
    },
);

# ids 5,6 are the entry for copied/mapped respectively
cmp_deeply [$filtered->toArray],
    [{
        event_created => isa('DateTime'),
        event_type => 'login',
        user       => 'fred',
        status     => 'YAY!',
        from_id    => 1,
        id         => 7,
        queue_id   => 6,
    }, 
    {
        event_created => isa('DateTime'),
        event_type => 'email',
        user       => 'pratesh',
        status     => 'YAY!',
        from_id    => 3,
        id         => 8,
        queue_id   => 6,
    }], 
    'filtering ok'
    or diag Dumper([$filtered->toArray]);

my $group = $raw->group( group => 
    code => sub {
        $_[0]->{event_type} eq $_[1]->{event_type}
    });

cmp_deeply [$group->toArray],
    [
      {
        event_created => isa('DateTime'),
        event_type => 'login',
        user       => 'fred',
        status     => 'ok',
        id         => 9,
        queue_id   => 8,
        from_id    => 1,
        count      => 2,
        'group' => 
          [
            {
            # HACK
            # event_created => isa('DateTime'),
            event_created => re('^\\d{4}-'),
            event_type => 'login',
            user       => 'fred',
            status     => 'ok',
            id         => 1,
            queue_id   => 1,
            }, 
            {
            # event_created => isa('DateTime'),
            event_created => re('^\\d{4}-'),
            event_type => 'login',
            user       => 'bill',
            status     => 'fail',
            id         => 2,
            queue_id   => 1,
            }
          ], 
       }
    ],
    'grouping ok'
    or die Dumper([$group->toArray]);

$raw->push({ 
    event_type => 'email',
    user       => 'jane',
    status     => 'ok',
});
$raw->push({ 
    event_type => 'logout',
    user       => 'fred',
    status     => 'ok',
});

##### NOW, the real test!
# destroy the connection and start again

my $conn2 = Harold::Connection::DBIC->new(
    dbic => $schema,
);
my $group2 = $conn2->getQ('group');

cmp_deeply [$group2->toArray],
    [
      {
        event_created => isa('DateTime'),
        event_type => 'login',
        user       => 'fred',
        status     => 'ok',
        from_id    => 1,
        id         => 9,
        queue_id   => 8,
        count      => 2,
        'group' => 
          [
            {
            # HACK
            # event_created => isa('DateTime'),
            event_created => re('^\\d{4}-'),
            event_type => 'login',
            user       => 'fred',
            status     => 'ok',
            id         => 1,
            queue_id   => 1,
            }, 
            {
            # event_created => isa('DateTime'),
            event_created => re('^\\d{4}-'),
            event_type => 'login',
            user       => 'bill',
            status     => 'fail',
            id         => 2,
            queue_id   => 1,
            }
          ], 
       },
       {
         event_created => isa('DateTime'),
         event_type => 'email',
         user       => 'pratesh',
         status     => 'ok',
         id         => 11,
         queue_id   => 8,
         from_id    => 3,
         count      => 2,
         group => 
          [
            {
            # event_created => isa('DateTime'),
            event_created => re('^\\d{4}-'),
            event_type => 'email',
            user       => 'pratesh',
            status     => 'ok',
            queue_id   => 9,
            id         => 10,
            from_id    => 3, # because was pushed on stack
            },
            {
            # event_created => isa('DateTime'),
            event_created => re('^\\d{4}-'),
            event_type => 'email',
            user       => 'jane',
            status     => 'ok',
            id         => 4,
            queue_id   => 1,
            },
          ]
       },
    ],
    'grouping ok'
    or die Dumper([$group2->toArray]);

done_testing;
