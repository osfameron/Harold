package Foo::Event::Completed;
use KiokuDB::Class;
extends 'Foo::Event::Base';

has object => (
    is => 'ro',
    isa => 'Int',
);

1;
