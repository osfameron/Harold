package Bar::Event::Created;
use KiokuDB::Class;
extends 'Bar::Event::Base';
use JSON::XS;

has object => (
    is => 'ro',
    isa => 'DBIx::Class::Core',
);

sub _build_title {
    my $self = shift;
    my $object = $self->object;
    return sprintf "Created %s (%d)", ref $object, $object->id;
}

sub _build_content {
    my $self = shift;
    my $object = $self->object;
    my %audit = (
        created => { $object->get_columns },
        by => $self->user->id,
        at => $self->datestamp . '',
    );
    return sprintf "Created %s\n%s", ref $object, encode_json(\%audit);
}

1;
