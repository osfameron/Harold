#!/usr/bin/perl

use strict; use warnings;
use Harold::List;
use Data::Dumper;
local $Data::Dumper::Indent = 1;
local $Data::Dumper::Maxdepth = 10;

use Test::More;

my $list = Harold::List->from_array(1..10);
my $map  = $list->map( sub { $_[0] + 1 });


use KiokuDB;
{
    my $kioku = KiokuDB->connect('hash');
    my $scope = $kioku->new_scope;

    is $map->head,             2;
    is $map->tail->head,       3;
    is $map->tail->tail->head, 4;

    $kioku->store(map => $map);

    my $map2 = $kioku->lookup('map');

    is_deeply [ $map2->take(3)->to_array ], [ 2,3,4 ];
    is_deeply [ $map2->takeWhile(sub { $_[0] < 6 })->take(10)->to_array ],
        [ 2..5 ];

    my $grep = $map->grep( sub { $_[0] % 2 });
    is_deeply [ $grep->take(10)->to_array ], [ 3,5,7,9,11 ];

    is $grep->foldl( sub { $_[0] + $_[1] }, 0 ), 35;
    is $grep->foldr( sub { $_[0] + $_[1] }, 0 ), 35;

    is_deeply [ $grep->concat($map2)->take(20)->to_array ], [ 3,5,7,9,11, 2..11 ];
    is_deeply [ $grep->cycle->take(20)->to_array ], 
        [ 3,5,7,9,11, 3,5,7,9,11, 3,5,7,9,11, 3,5,7,9,11 ];
}

done_testing;
