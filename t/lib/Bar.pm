package Bar;
use Moose;
use Method::Signatures::Simple;

has config => (
    is => 'rw',
    isa => 'HashRef',
    lazy => 1,
    default => sub {
        {
            dsn => 'dbi:SQLite:dbname=:memory:',
        }
    },
);
has db => (
    is  => 'ro',
    isa => 'BarDB',
    lazy => 1,
    default => sub {
        my $self = shift;
        require BarDB;
        my $db = BarDB->connect( $self->config->{dsn} );
        $db->deploy(); # for test

        return $db;
    },
);

has event => (
    is => 'ro',
    isa => 'Bar::Event',
    lazy => 1,
    default => sub {
        require Bar::Event;
        return Bar::Event->new;
    },
);

has kioku => (
    is => 'ro',
    isa => 'KiokuDB',
    lazy => 1,
    default => sub {
        my $self = shift;
        require KiokuDB;
        my $kioku = KiokuDB->connect( 
            $self->config->{dsn},
            schema => 'BarDB',
            create => 1,
        );
        $self->scope( $kioku->new_scope );
        return $kioku;
    },
);

has scope => (
    is => 'rw',
);

1;
