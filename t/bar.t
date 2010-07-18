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
my $db = $bar->db;
my $admin   = $db->resultset('User')->create( { name => 'Administrator' } );
my $johndoe = $db->resultset('User')->create( { name => 'John Doe' } );
my $dvd     = $db->resultset('Dvd') ->create( { name => 'Dogville', user => $johndoe } );

my $foo = Foo->new( foo => $dvd );
my $kioku = $bar->kioku;
$kioku->store(foo => $foo );

my $foo2 = $kioku->lookup( 'foo' );
warn Dumper( { $foo2->foo->get_columns } );

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
