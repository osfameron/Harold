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

    method get_or_createQ (Str :$name, Harold::Queue :$from, Str :$table) {
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

    has _queues => (
        traits  => ['Hash'],
        isa     => 'HashRef[Harold::Queue]',
        is      => 'ro',
        default => sub {},
        handles => {
            _getQ => 'get',
            _setQ => 'set',
        },

    );

    has _result_sets => (
        traits  => ['Hash'],
        isa     => 'HashRef[DBIx::Class::ResultSet]',
        is      => 'ro',
        default => sub {},
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

    method getQ (Str $name) {
        if (my $queue = $self->_getQ($name)) {
            return $queue;
        }

        my $row = $self->dbic->resultset($self->_table_name)
            ->find($name)
            or return;

        return $self->_newQ($name, row=>$row);
    }

    method createQ (Str :$name, Harold::Queue :$from, Str :$table, HashRef :$opts) {
        $name //= do {
            require Data::UUID;
            Data::UUID->new->create_hex;
        };

        my $row = $self->dbic->resultset($self->_table_name)
            ->create({
                name  => $name,
                table => $table // $self->default_table,
                from  => $from ? $from->queue_id : undef,
                index => 0,
            }); # will die on duplicate

        return $self->_newQ(name=>$name, row=>$row, from=>$from, opts=>$opts);
    }

    method _newQ (Str :$name!, $row!, Harold::Queue :$from, :$table, HashRef :$opts) {

        $table //= $row->table;

        my $rs = $self->dbic->resultset($table)
            or die "No such table $table";

        if ($rs->result_source->has_column('queue_id')) {
            $rs = $rs->search({ queue_id => $row->id });
        }
        $self->_set_rs( $table, $rs );

        if (my $from_row = $row->from) {
            $from //= $self->getQ($from_row->name);
        }

        my $class;
        my %data = (
            name       => $name,
            connection => $self,
            queue_id   => $row->queue_id,
            table      => $table,
        );
        if ($from) {
            $class = $self->derived_class;
            %data = (
                %data,
                from       => $from,
                code       => $self->inflate_code($row->code),
                index      => $row->index,
            );
        }
        else {
            $class = $self->primary_class;
        }

        my $queue = $class->new( %data );
        $self->_setQ($name, $queue);
        return $queue;
    }

    method deriveQ (Harold::Queue :$from!, CodeRef :$code!, Str :$name, HashRef :$opts) {

        my $queue = $self->createQ(
            %{ $opts || {} },
            connection => $self,
            from       => $from,
            code       => $code,
            $name ? ( name => $name ) : (),
        );

        $queue->update;
        return $queue;
    }

    method range () {
        die "EEEK";
    }

    method push (Harold::Queue $queue, HashRef $hash) {
        my $rs = $self->_get_rs($queue->name)
            or die "No resultset for queue " . $queue->name;

        my %data = map { $_ => undef } $rs->result_source->columns;
        my %hash = (%$hash, queue_id => $queue->queue_id);

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

    method length () {
        return $self->connection->length($self);
    }

    method range (Int $from, Int $to) {
        $self->connection->range( $self, 0, -1 );
    }

    method toArray () {
        $self->range( 0, -1 );
    }

    method _push ($value) {
        $self->connection->push($self, $value);
    }
    method update {
        # no-op
    }

    # trivial derivation
    method copy (Str :$name, HashRef :$opts) {
        $self->connection->deriveQ(
            %{$opts || {}},
            from => $self,
            name => $name,
            code => sub {
                my ($element, $stack) = @_;
                return ([$element], $stack);
            },
        );
    }

    method map (Str :$name, CodeRef :$code, HashRef :$opts) {
        $self->connection->deriveQ(
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
       $self->connection->deriveQ(
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
        $self->connection->deriveQ(
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
        $self->connection->deriveQ(
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
    has _index => (
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
        my $new_index = $self->from->length;

        # TODO handle case where another client has updated us in the meantime

        my @list  = $self->from->lrange( $self->_index, -1 );
        my $stack = [ $self->stack_as_array ];
        my $code = $self->code;
        for my $elem (@list) {
            (my $elems, $stack) = $code->($elem, $stack);
            
            for my $new (@{ $elems || [] }) {
                $self->rpush( $new );
            }
        }
        # reset the stack
        $self->connection->del( $self->stack_name );
        for my $elem (@$stack) {
            $self->add_to_stack($elem);
        }
        $self->_index( $new_index );
        $self->connection->hset( $self->meta_name, 'index', $self->from->name );
    }
}

package main;
use strict;
use warnings;
use Test::More;
