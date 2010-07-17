package Foo::Event::Base;
use KiokuDB::Class;
extends 'Harold::Event::Base';

has user => (
    is => 'ro',
    isa => 'Maybe[User]',
);

has subject => (
    is => 'ro',
    isa => 'Any',
);

1;
