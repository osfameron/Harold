package Harold::Timeline;
use KiokuDB::Class;
use MooseX::Types::DateTime;
use Harold::Event;
use Harold::List;
use Scalar::Util 'refaddr';

has 'store_as' => (
    is  => 'rw',
    isa => 'Maybe[Str]',
);

has from_feed => (
    is  => 'ro',
    isa => 'Maybe[Str]',
);

has list => (
    is      => 'rw',
    isa     => 'Harold::List',
    default => sub { Harold::List->empty },
);

has make_list => (
    traits => ['Code'], 
    handles => { make_list => 'execute' },
    isa => 'CodeRef',
);

has from_feed_up_to => (
    is  => 'rw',
    isa => 'Maybe[Harold::Event::Base]',
);

has from_root_up_to => (
    is => 'rw',
    isa => 'Maybe[Harold::Event::Base]',
);

sub create {
    my ($class, $kioku, %params) = @_;

    my $self = $class->new(%params);

    my $store_as = $self->store_as or return;
    $kioku->store( $store_as, $self );

    $self->update($kioku);
    return $self;
}


sub add_event {
    # only valid for root
    my ($self, $event) = @_;
    $self->list( $self->list->prepend($event) );
}

sub up_to_date {
    my ($self, $kioku, $root) = @_;

    return 1 unless $self->from_feed;     # root list cannot be updated in this way
    return unless $self->from_root_up_to; # if new, then must be updated!
                                          # check if it's been updated
    return 1 if refaddr $root->list->head == refaddr $self->from_root_up_to;
}

sub update {
    my ($self, $kioku, $root) = @_;

    $kioku->txn_do( sub {
        $root ||= $kioku->lookup('root');

        return if $self->up_to_date( $kioku, $root );

        my $from = $kioku->lookup( $self->from_feed );
        $from->update($kioku, $root);

        my $from_feed_up_to = $self->from_feed_up_to;
        my $new = $from_feed_up_to ?
            $from->list->takeWhile( 
                sub { refaddr $_[0] != refaddr $from_feed_up_to })
            : $from->list->take(100); # TODO make more flexible

        my $new_list = $self->make_list( $new );

        my $whole_list = $new_list->concat($self->list);

        $self->list($whole_list);
        $self->from_feed_up_to( $from->list->head );
        $self->from_root_up_to( $root->list->head );

        $kioku->store($self) if $self->store_as;
    });
}

1;
