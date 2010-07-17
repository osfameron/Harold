package Harold::List;
use KiokuDB::Class;

my $empty;
sub empty { return $empty ||= Harold::List::Empty->new }

sub prepend {
    my ($self, $head) = @_;
    return $self->node($head, $self);
}

sub node {
    my $class = shift;
    return $class->empty unless @_;
    my ($head, $tail) = @_;
    $tail ||= $class->empty;

    return Harold::List::Node->new({
        head  => $head,
        _tail => $tail,
        });
}

sub from_array {
    my $self = shift;
    my $class = (ref $self) || $self;
    if (@_) {
        my $head = shift;
        return $self->node( $head, scalar $class->from_array(@_));
    }
    else {
        return $class->empty;
    }
}

package Harold::List::Node;
use KiokuDB::Class;

extends 'Harold::List';

has 'head' => (
    is  => 'ro',
    isa => 'Any',
);

has '_tail' => (
    traits  => ['KiokuDB::Lazy'],
    is      => 'rw',
    isa     => 'Harold::List | CodeRef',
);

sub tail {
    my $self = shift;
    my $tail = $self->_tail;
    if (ref $tail eq 'CODE') {
        my $newtail = $tail->($self);
        $self->_tail($newtail);
        return $newtail;
    }
    else {
        return $tail;
    }
}

sub to_array {
    my ($list) = @_;
    return ($list->head, $list->tail->to_array);
}

sub map {
    my ($self, $f) = @_;

    return $self->node(
        $f->($self->head),
        sub {
            $self->tail->map($f)
        });
}

sub grep {
    my ($self, $f) = @_;

    my $head = $self->head;

    return $f->($head) ?
        $self->node(
            $head, 
            sub {
                $self->tail->grep($f)
            }) 
        : $self->tail->grep($f);
}

sub foldl {
    my ($self, $f, $init) = @_;
    return $self->tail->foldl( $f, $f->( $init, $self->head ) );
}

sub foldr {
    # f x (foldr f z xs)
    my ($self, $f, $init) = @_;
    return $f->(
        $self->head,
        $self->tail->foldr( $f, $init )
        );
}

sub cycle {
    my ($self, $list) = @_;
    return $self->node ($self->head, sub { $self->tail->cycle($list || $self) });
}

sub concat {
    my ($self, $list) = @_;
    return $self->foldr( sub { $_[1]->prepend($_[0]) }, $list );
}

sub take {
    my ($list, $count) = @_;
    return $list->empty unless $count;
    return $list->node($list->head, $list->tail->take($count-1));
}

sub takeWhile {
    my ($list, $f) = @_;
    my $head = $list->head;
    if ($f->($head)) {
        return $list->node( $head, scalar $list->tail->takeWhile($f));
    }
    else {
        return $list->empty;
    }
}

package Harold::List::Empty;
use KiokuDB::Class;
extends 'Harold::List';

sub head  { die "Empty lists have no head" }
sub tail  { die "Empty lists have no tail" }
sub to_array { return () }
sub take  { return shift }
sub map   { return shift }
sub grep  { return shift }
sub takeWhile { return __PACKAGE__->empty }
sub concat {
    my ($self, $list) = @_;
    return $list;
}
sub foldl {
    my ($self, $f, $init) = @_;
    return $init;
}
sub foldr {
    my ($self, $f, $init) = @_;
    return $init;
}
sub cycle {
    my ($self, $list) = @_;
    return $list->cycle();
}

1;
