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

$bar->create_user('John Doe');

local $Data::Dumper::Maxdepth = 2;
local $Data::Dumper::Indent = 1;
say $bar->root_timeline->list->head->xml_atom_entry->as_xml;

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
