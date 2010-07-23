#!/usr/bin/perl
use strict; use warnings;

use Test::More;
use feature 'say';
use Data::Dumper;

use lib 't/lib';
use Bar;

package Foo;
use KiokuDB::Class;
has 'foo' => (
    is => 'rw',
);

package main;

my $bar = Bar->new;
$bar->deploy;

$bar->create_user('John Doe');
$bar->create_user('Dylan Dog');
$bar->create_user('Martin Mystere');

my $do = $bar->create_timeline(
    Do =>
    from_feed => 'root',
    make_list => sub {
        my $root = shift;
        $root->grep( sub {
            my $ev = shift;
            warn ref $ev;
            if ($ev->isa('Bar::Event::Created')) {
                my $obj = $ev->object;
                return unless $obj->isa('BarDB::Result::User');
                return $obj->name=~/Do/;
            }
            }) 
        });
$do->update($bar->kioku);

local $Data::Dumper::Maxdepth = 2;
local $Data::Dumper::Indent = 1;
$bar->kioku->store($bar->root_timeline);
say $bar->root_timeline->list->head->xml_atom_entry->as_xml;
say "=------";

my $tl = $bar->get_timeline('Do');
$tl->update( $bar->kioku );
say join "\n", map { $_->xml_atom_entry->as_xml }
    $tl->list->to_array;

__END__


{
    my $create = 1;
    my $kioku = KiokuDB->connect(
        "dbi:mysql:dbname=vfkm_dev",
        user => 'root',
        password => 'password',
        create => $create);

    # $kioku->backend->deploy({ producer_args => { mysql_version => 4 } }) if $create;

    my $scope = $kioku->new_scope;

    my $foo = Bar->new( foo => 'wibble' );
    $kioku->store( foo => $foo );
}
