package Bar;
use Moose;
use Method::Signatures::Simple;

# Note that using Bar will *deploy* an in-memory app
# if you're cargo-culting this test to create an actual app,
# you'd want to remove the initialization/deploying from the default subs!

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

        $db->resultset('User')->create({ name => 'admin' });

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

has root_timeline => (
    is => 'ro',
    isa => 'Harold::Timeline',
    lazy => 1,
    default => sub {
        my $self = shift;
        require Harold::Timeline;
        return Harold::Timeline->create(
            $self->kioku,
            store_as => 'root',
        );
    },
);

has scope => (
    is => 'rw',
);

has logged_in_user => (
    is => 'rw',
    isa => 'Maybe[BarDB::Result::User]',
    lazy => 1,
    default => sub {
        # for purpose of testing;
        my $self = shift;
        $self->db->resultset('User')->find({ name => 'admin' });
    },
);

method login ($user) {
    $self->logged_in_user( $user );
}

method raise_event ($type, %opts) {
    my $event = $self->event->raise( $type,
        user => $self->logged_in_user,
        %opts );
    $self->root_timeline->add_event($event);
    return $event;
}

method create_user ($name) {
    my $user = $self->db->resultset('User')->create({ name => $name });
    $self->raise_event( Created =>
        object => $user );
    return $user;
}

1;
