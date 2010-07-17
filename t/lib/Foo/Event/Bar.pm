package Foo::Event::Bar;
use KiokuDB::Class;
extends 'Harold::Event::Base';

sub _build_content {
    my $self = shift;
    return sprintf "RARR %s", $self->text;
}

1;
