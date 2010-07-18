package Harold::List;
use KiokuDB::Class;

=head1 NAME

Harold::List - lazy list class that plays well with KiokuDB

=head1 SYNOPSIS

 use PerlX::MethodCallWithBlock;

 my $list = Harold::List->from_array( 1..10 );
 my $odds = $list->grep { shift % 2 };
 my $cycle = $odds->cycle; # infinite list
 my $map   = $cycle->map { shift + 1 };
 say join ',' => $map->take(5)->to_array;

=head1 DESCRIPTION

This is a lazy list class, loosely modelled on the Haskell prelude, and intended
to play nicely with KiokuDB.

Laziness is implemented using closures.  C<tail> will handle a subroutine 'promise'.
Tails are marked as with the C<KiokuDB::Lazy> trait, so they won't get retrieved
unless requested.

Note that (for now) tails aren't automatically saved to KiokuDB.  You'll normally
save a whole list by C<store>'ing the head of the list.

=head1 METHODS

=over 4

=item C<empty>

A class method that returns an empty list;

 my $empty = Harold::List->empty;

=cut

my $empty;
sub empty { return $empty ||= Harold::List::Empty->new }

=item C<node>

Class method to create a new list:

 my $list = Harold::List->node( $head, $tail );
 my $list = Harold::List->node( $head );        # Empty tail
 my $list = Harold::List->node( );              # Same as ->empty;

=cut

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

=item C<from_array>

Generate a list from a Perl array;

 my $list = Harold::List->from_array( 1..10 );

=cut

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

=item C<prepend>

Returns a new list with the value supplied as its head.

 my $new = $list->prepend( $new_head );

=cut

sub prepend {
    my ($self, $head) = @_;
    return $self->node($head, $self);
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

=item C<head>

Returns the head of the list.

 my $list = Harold::List->from_array( 1..10 );
 say $list->head; # '1'

=item C<tail>

Returns the tail of the list

 say $list->tail->head; # '2'

=cut

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

=item C<to_array>

Returns a perl array.  Don't do this for infinite lists!

 my @array = $list->to_array;

=cut

sub to_array {
    my ($list) = @_;
    return ($list->head, $list->tail->to_array);
}

=item C<map>

Transform one list to another.  Unlike Perl's builtin map, this takes a subroutine reference
(rather than a block) and uses C<@_> and C<return> for its values.

 my $map = $list->map( sub { $_[0] + 1 } );

 # or if you want sugar
 use PerlX::MethodCallWithBlock;
 my $map = $list->map { $_[0] + 1 };

=cut

sub map {
    my ($self, $f) = @_;

    return $self->node(
        $f->($self->head),
        sub {
            $self->tail->map($f)
        });
}

=item C<grep>

Filter a list.

 my $grep = $list->grep { $_[0] =~ /foo/ };

=cut

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

=item C<foldl>, C<foldr>

Reduce a list by progressively applying a function to it.

 my $sum = $list->foldl(sub{ $_[0] + $_[1] }, 0);

=cut

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

=item C<cycle>

Continually repeat the list.

 my $cycle = Harold::List->from_array(1..3)->cycle;

 say join ',', $cycle->take(7)->to_array; '1,2,3,1,2,3,1'

=cut

sub cycle {
    my ($self, $list) = @_;
    return $self->node ($self->head, sub { $self->tail->cycle($list || $self) });
}

=item C<concat>

Concatenate 2 lists.

 my $new = $list->concat($other_list);

=cut

sub concat {
    my ($self, $list) = @_;
    return $self->foldr( sub { $_[1]->prepend($_[0]) }, $list );
}

=item C<take>

Return a number of elements from a list.  This is useful when turning an infinite list back into a finite Perl array.

 say join ',' => $list->take(5)->to_array;

=cut

sub take {
    my ($list, $count) = @_;
    return $list->empty unless $count;
    return $list->node($list->head, $list->tail->take($count-1));
}

=item C<takeWhile>

Take from a list while a condition is true.

 my $lt5 = $list->takeWhile( sub { $_[0] < 5 } );

=back

=cut

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

=head1 SEE ALSO

L<Harold>

=head1 AUTHOR and COPYRIGHT

 (C) osfameron@cpan.org 2010

=cut

1;
