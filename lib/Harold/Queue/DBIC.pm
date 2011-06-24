use MooseX::Declare;
use Moose::Util::TypeConstraints;
BEGIN { 
    role_type 'Harold::Connection';
    class_type 'Harold::Queue';
    }

role Harold::Connection {
    use Data::Dump::Streamer;

    requires 'getQ';    # (Str  $name)
    requires 'createQ'; # (Str :$name, Str|Harold::Queue :$from, Str :$table) {
    requires 'deriveQ'; # ...

    method get_or_createQ (Str :$name, Harold::Queue :$from, Str :$tablesource) {
        return $self->getQ($name) 
            // $self->createQ(@_);
    }

    requires 'range'; # (Harold::Queue $queue, Int $from, Int $to)
    requires 'push';  # (Harold::Queue $queue, $value)

    # using Data::Dump::Streamer, see caveats!
    method inflate_code (Str $codestring) {
        my $CODE1;
        eval $codestring;
        return $CODE1;
    }
    method deflate_code (CodeRef $coderef) {
        my $codestring = Dump($coderef)->Out;
        return $codestring;
    }

    use constant primary_class => 'Harold::Queue::Primary';
    use constant derived_class => 'Harold::Queue::Derived';
}

class Harold::Connection::DBIC with Harold::Connection {
    has _table_name => (
        is      => 'ro',
        isa     => 'Str',
        default => 'Queues',
    );
    has default_tablesource => (
        is      => 'ro',
        isa     => 'Str',
        default => 'Misc',
    );

    has _queues => (
        traits  => ['Hash'],
        isa     => 'HashRef[Harold::Queue]',
        is      => 'ro',
        default => sub {{}},
        handles => {
            _getQ => 'get',
            _setQ => 'set',
        },

    );

    has _result_sets => (
        traits  => ['Hash'],
        isa     => 'HashRef[DBIx::Class::ResultSet]',
        is      => 'ro',
        default => sub {{}},
        handles => {
            _get_rs => 'get',
            _set_rs => 'set',
        },
    );

    has dbic => (
        is => 'ro',
        isa => 'DBIx::Class::Schema',
    );

    has json => (
        is      => 'ro',
        default => sub { 
            JSON::XS
                ->new
                ->convert_blessed(1)
        },
        handles => {
            encode_json => 'encode',
            decode_json => 'decode',
        },
    );

    method getRow (Str $name) {
        my $row = $self->dbic->resultset($self->_table_name)
            ->find({ name => $name });
    }

    method getQ (Str $name) {
        if (my $queue = $self->_getQ($name)) {
            return $queue;
        }

        my $row = $self->getRow($name) or return;

        return $self->_newQ($name, $row);
    }

    method createQ (Str :$name?, Str :$tablesource?, :$from?, CodeRef :$code?, HashRef :$opts?) {
        $name //= do {
            require Data::UUID;
            Data::UUID->new->create_hex;
        };

        $tablesource //= $self->default_tablesource;

        my $row = $self->dbic->resultset($self->_table_name)
            ->create({
                name  => $name,
                tablesource => $tablesource,
                $from ? (from_queue_id => $from->queue_id, pos => 0) : (),
                $code ? (codestring => $self->deflate_code($code)) : (),
            }); # will die on duplicate

        $row->discard_changes;

        my @params = ($name, $row);
        if ($opts) { $params[2] = $opts }
        if ($from) { $params[3] = $from }
        return $self->_newQ( @params );
    }

    method _newQ (Str $name, $row, Maybe[HashRef] $opts?, Harold::Queue $from?) {

        my $tablesource = $row->tablesource;

        my $rs = $self->dbic->resultset($tablesource)
            or die "No such tablesource $tablesource";

        if ($rs->result_source->has_column('queue_id')) {
            $rs = $rs->search({ queue_id => $row->id });
        }
        $self->_set_rs( $name, $rs );

        if (my $from_row = $row->from) {
            $from //= $self->getQ($from_row->name);
        }

        my $class;
        my %data = (
            name       => $name,
            connection => $self,
            queue_id   => $row->queue_id,
            tablesource      => $tablesource,
        );
        if ($from) {
            $class = $self->derived_class;
            %data = (
                %data,
                from       => $from,
                code       => $self->inflate_code($row->codestring),
                pos      => $row->pos,
            );
        }
        else {
            $class = $self->primary_class;
        }

        my $queue = $class->new( %data );
        $self->_setQ($name, $queue);
        return $queue;
    }

    # method createQ (Str :$name?, Str :$tablesource?, :$from?, HashRef :$opts?) {
    method deriveQ (Harold::Queue $from, CodeRef $code, HashRef $opts? = {}) {

        my $queue = $self->createQ(
            %$opts,
            from       => $from,
            code       => $code,
        );

        $queue->update;
        return $queue;
    }

    method range (Harold::Queue $queue, Int $from, Int $to) {
        my $rs = $self->_get_rs($queue->name)
            or die "No resultset for queue " . $queue->name;

        my @rows = $rs->search({ 
            id => {
                '>=', $from,
                '<=', $to,
            }
        })->all;

        # should do something like HashRefInflator?
        return map {
            my %columns = $_->get_inflated_columns;
            my %json = %{ delete $columns{json} };
            %columns = (%columns, %json);
            \%columns;
        } @rows;
    }
    method set_pos (Harold::Queue $queue, Int $pos) {
        my $name = $queue->name;
        my $row = $self->getRow($name) or die "No such name $name";
        $row->update({ pos => $pos });
    }

    method maxpos (Harold::Queue $queue) {
        my $rs = $self->_get_rs($queue->name)
            or die "No resultset for queue " . $queue->name;

        return $rs->search(
            {},
            {
               select => \'max(id)',
               as     => 'maxid',
            })->single->get_column('maxid');
    }

    method push (Harold::Queue $queue, HashRef $hash) {
        my $rs = $self->_get_rs($queue->name)
            or die "No resultset for queue " . $queue->name;

        my %data = map { $_ => undef } $rs->result_source->columns;
        my %hash = (%$hash, queue_id => $queue->queue_id);

        if (my $id = delete $hash{id}) {
            # we don't overwrite the primary key, but store it in "from_id"
            # (unless from_is is already set, in which case we simply pass that value through)
            $hash{from_id} //= $id;
        }

        for my $key (keys %hash) {
            if (exists $data{$key}) {
                $data{$key} = delete $hash{$key};
            }
        }
        # e.g. don't set a 'json' key unless you want to override!
        $data{json} //= \%hash;

        $rs->create( \%data );
    }

}

class Harold::Queue {
    use MooseX::MultiMethods;
    use JSON::XS;

    has queue_id => (
        is => 'ro',
        isa => 'Int',
    );

    has name => (
        is  => 'ro',
        isa => 'Str',
    );

    has connection => (
        is      => 'ro',
        isa     => 'Harold::Connection',
        handles => [ ],
    );

    method maxpos () {
        return $self->connection->maxpos($self);
    }

    method range (Int $from, Int $to) {
        $self->connection->range( $self, $from, $to );
    }

    method rangeFrom (Int $from) {
        $self->range( $from, $self->maxpos );
    }

    method toArray () {
        $self->range( 0, $self->maxpos );
    }

    method _push ($value) {
        $self->connection->push($self, $value);
    }
    method update {
        # no-op
    }

    # trivial derivation
    # method deriveQ (Harold::Queue $from, CodeRef $code, Str $name?, HashRef $opts?) {
    method copy (Str $name?, HashRef $opts?) {
        my $code = 
            sub {
                my ($element, $stack) = @_;
                return ([$element], $stack);
            };

        $self->connection->deriveQ( $self, $code, { name => $name, %{ $opts || {} }});
    }

    method map (Str :$name, CodeRef :$code, HashRef :$opts) {
        $self->connection->_deriveQ(
            %{$opts || {}},
            from => $self,
            name => $name,
            code => sub {
                my ($element, $stack) = @_;
                return ([$code->($element)], $stack);
            },
        );
    }
    method filter (Str :$name, CodeRef :$predicate, HashRef :$opts) {
       $self->connection->_deriveQ(
            %{$opts || {}},
            from => $self,
            name => $name,
            code => sub {
                my ($element, $stack) = @_;
                my $result = $predicate->($element) ? [$element] : [];
                return ($result, $stack);
            },
        );
    }
    method concatMap (Str :$name, CodeRef :$code, HashRef :$opts) {
        # coderef must return an arrayref!
        $self->connection->_deriveQ(
            %{$opts || {}},
            from => $self,
            name => $name,
            code => sub {
                my ($element, $stack) = @_;
                my $result = $code->($element);
                die ref $result unless ref $result eq 'ARRAY';
                return ($result, $stack);
            },
        );
    }

    # now let's actually use this stack thing then...
    method group (Str :$name, CodeRef :$code, HashRef :$opts) {
        $self->connection->_deriveQ(
            %{$opts || {}},
            from => $self,
            name => $name,
            code => sub {
                my ($element, $stack) = @_;
                my @stack = @$stack;
                if (@stack &&
                    (! $code->($stack->[-1], $element))) 
                {
                    # grouping done, so let's push back these elements
                    return ( [\@stack], [$element] );
                }
                return ([], [@stack, $element]);
            },
        );
    }
}

class Harold::Queue::Primary extends Harold::Queue {
    method push ($value) {
        $self->_push($value);
    }
}

class Harold::Queue::Derived extends Harold::Queue {
# you are not expected to construct a Q::D directly with ->new()
# rather use derive_from() or fetch()

    use MooseX::MultiMethods;
    use Data::Dump::Streamer;

    has code => (
        is  => 'ro',
        isa => 'CodeRef',
        # sub ($element, \@stack) { return (\@elements, \@new_stack) }
    );
    has from => (
        is  => 'ro',
        isa => 'Harold::Queue',
    );
    has pos => (
        is      => 'rw',
        isa     => 'Int',
        default => 0,
    );
    has stack => (
        is      => 'ro',
        isa     => 'Harold::Queue',
        lazy    => 1,
        default => sub {
            my $self = shift;
            Harold::Queue->new(
                name => $self->stack_name,
            );
        },
        handles => {
            add_to_stack   => 'rpush',
            stack_as_array => 'toArray',
        }
    );

    method stack_name {
        return '__STACK__:' . $self->name;
    }

    method update {
        $self->from->update;
        my $new_pos = $self->from->maxpos;

        # TODO handle case where another client has updated us in the meantime

        my @list  = $self->from->rangeFrom( $self->pos );
        my $stack = []; # my $stack = [ $self->stack_as_array ];
        my $code = $self->code;
        for my $elem (@list) {
            (my $elems, $stack) = $code->($elem, $stack);
            
            for my $new (@{ $elems || [] }) {
                $self->_push( $new );
            }
        }
        # reset the stack
        # $self->connection->del( $self->stack_name );
        # for my $elem (@$stack) {
            # $self->add_to_stack($elem);
        # }
        $self->pos( $new_pos );
        $self->connection->set_pos( $self, $new_pos );
    }
}

package main;
use strict;
use warnings;
use Test::More;
