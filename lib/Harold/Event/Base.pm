package Harold::Event::Base;
use KiokuDB::Class;
use MooseX::Types::DateTime;
use XML::Atom::Entry;

has datestamp => (
    is  => 'ro',
    isa => 'DateTime',
    default => sub { DateTime->now() },
);

has text => (
    is  => 'ro',
    isa => 'Str',
);

has title => (
    is => 'ro',
    isa => 'Str',
    lazy_build => 1,
);

has content => (
    is => 'ro',
    isa => 'Str',
    lazy_build => 1,
);
has xml_atom_entry => (
    is => 'ro',
    isa => 'XML::Atom::Entry',
    lazy_build => 1,
);

sub _build_xml_atom_entry {
    my $self = shift;
    require XML::Atom::Entry;
    my $entry = XML::Atom::Entry->new;
    $entry->title  ( $self->title );
    $entry->content( $self->content );
    return $entry;
}

sub _build_title {
    my $self = shift;
    return $self->text;
}

sub _build_content {
    my $self = shift;
    return sprintf "%s\n%s", $self->text, $self->datestamp;
}

1;
