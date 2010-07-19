package Bar::Event::Base;
use KiokuDB::Class;
extends 'Harold::Event::Base';

has user => (
    is => 'ro',
    isa => 'Maybe[BarDB::Result::User]',
);

has subject => (
    is => 'ro',
    isa => 'Any',
);

1;
