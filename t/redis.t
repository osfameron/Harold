# another play with Harold, using Redis queues

use MooseX::Declare;
use Moose::Util::TypeConstraints;
BEGIN { class_type 'Redis' }

class Queue {
    use MooseX::MultiMethods;
    use JSON::XS;

    has name => (
        is  => 'ro',
        isa => 'Str',
        default => sub {
            require Data::UUID;
            Data::UUID->new->create_hex;
        },
    );

    has connection => (
        is      => 'ro',
        isa     => 'Redis',
        default => sub { 
            require Redis;
            Redis->new() 
        },
    );

    has _json => (
        is      => 'ro',
        default => sub { 
            JSON::XS
                ->new
                ->allow_nonref(1);
        },
        handles => {
            encode_json => 'encode',
            decode_json => 'decode',
        },
    );

    method meta_name {
        return '__META__:' . $self->name;
    }

    method fetch ($self_or_class: Str $name, Redis :$connection) {
        if (ref $self_or_class) {
            $connection //= $self_or_class->connection;
        }
        my $self = $self_or_class->new(
            connection => $connection,
            name       => $name,
        );

        $connection = $self->connection;
        die "No such list $name" unless $connection->exists($name);

        my $class;
        if ($connection->exists($self->meta_name)) {
            if($connection->hexists($self->meta_name, 'from')) {
                $class = __PACKAGE__ . '::Derived';
                $self->{code} = eval
                    $connection->hget($self->meta_name, 'code');
                bless $self, $class;

                $self->update;
            }
        }

        if (!$class) {
            $class = __PACKAGE__ . '::Primary';
            bless $self, $class;
        }

        return $self; 
    }

    method length () {
        return $self->llen();
    }

    method toArray () {
        $self->lrange( 0, $self->length );
    }

    # proxy methods
    method lrange ($start, $end) { 
        map $self->decode_json($_),
            $self->connection->lrange($self->name, $start, $end);
    }
    method rpush ($value) {
        my $encoded = $self->encode_json($value);
        $self->connection->rpush($self->name, $encoded);
    }
    method llen () { 
        $self->connection->llen($self->name);
    }
    method update {
        # no-op
    }

    # trivial derivation
    method copy (Str :$name) {
        Queue::Derived->derive_from(
            from => $self,
            name => $name,
            code => sub {
                my ($element, $stack) = @_;
                return ([$element], $stack);
            },
        );
    }

    method map (Str :$name, CodeRef :$code) {
        Queue::Derived->derive_from(
            from => $self,
            name => $name,
            code => sub {
                my ($element, $stack) = @_;
                return ([$code->($element)], $stack);
            },
        );
    }
    method filter (Str :$name, CodeRef :$predicate) {
        Queue::Derived->derive_from(
            from => $self,
            name => $name,
            code => sub {
                my ($element, $stack) = @_;
                my $result = $predicate->($element) ? [$element] : [];
                return ($result, $stack);
            },
        );
    }
    method concatMap (Str :$name, CodeRef :$code) {
        # coderef must return an arrayref!
        Queue::Derived->derive_from(
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
    method group (Str :$name, CodeRef :$code) {
        Queue::Derived->derive_from(
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

class Queue::Primary extends Queue {
    method push ($value) {
        $self->rpush($value);
    }
}

class Queue::Derived extends Queue {
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
        isa => 'Queue',
    );
    has _index => (
        is      => 'rw',
        isa     => 'Int',
        default => 0,
    );
    has stack => (
        is      => 'ro',
        isa     => 'Queue',
        lazy    => 1,
        default => sub {
            my $self = shift;
            Queue->new(
                name => $self->stack_name,
            );
        },
        handles => {
            add_to_stack   => 'rpush',
            stack_as_array => 'toArray',
        }
    );

    method derive_from ($class: Queue :$from!, CodeRef :$code!, Maybe[Str] :$name?) {
        my $self = $class->new(
            connection => $from->connection,
            _json      => $from->_json,
            from       => $from,
            code       => $code,
            $name ? ( name => $name ) : (),
        );
        # 
        $self->connection->hset( 
            $self->meta_name, from => $from->name );
        my $codestring = Dump($code)->Out;
        warn "RARR $codestring";
        $self->connection->hset( 
            $self->meta_name, code => $codestring);

        $self->update;
        return $self;
    }
    # multi method derive_from ($class: Str $from, CodeRef $code) {
        # die "Coercing $from isn't yet supported";
    # }

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
use Data::Dumper;

my $queue = Queue::Primary->new(); # random name
diag $queue->name;

$queue->push( 1 );
$queue->push( { foo => 'bar' } );

is $queue->length, 2, 'length ok';;
is_deeply [$queue->toArray], 
          [ 1, { 'foo' => 'bar' } ],
          'structure ok';

my $copy = $queue->copy();
is_deeply [$copy->toArray], 
          [ 1, { 'foo' => 'bar' } ],
          'copied structure ok'
      or diag Dumper([ $copy->toArray ]);

$queue->push( 'last' );
$copy->update;

is_deeply [$copy->toArray],
          [ 1, { 'foo' => 'bar' }, 'last' ],
          'updated ok';

my $nums = Queue::Primary->new();
for (1..10) { $nums->push($_) }

my $x3 = $nums->map( code => sub { $_[0] * 3 } );
is_deeply [$x3->toArray],
          [3,6,9,12,15,18,21,24,27,30],
          '3 times table';

# but wait!  times tables go to *12* as any fule know
for (11..12) { $nums->push($_) }
$x3->update;
is_deeply [$x3->toArray],
          [3,6,9,12,15,18,21,24,27,30,33,36],
          '... much better';

for (13..15) { $nums->push($_) }
my $fizzbuzz = $nums->concatMap(
    code => sub {
        my $num = shift;
        my @fb;
        push @fb, 'fizz' unless $num % 3;
        push @fb, 'buzz' unless $num % 5;
        return \@fb if @fb; 
            # yes, I know, this isn't classic fizzbuzz,
            # but want to test concatMap - patches welcome
        return [$num];
    }
);
is_deeply [$fizzbuzz->toArray],
          [1,      2,      'fizz', 4,      'buzz',
           'fizz', 7,      8,      'fizz', 'buzz',
           11,     'fizz', 13,     14,     ('fizz','buzz')],
          'Fizzbuzz-ish';

my $zz = $fizzbuzz->filter( predicate => sub { $_[0] =~ /zz/ } );
is_deeply [$zz->toArray],
          ['fizz', 'buzz',
           'fizz', 'fizz', 'buzz',
           'fizz', 'fizz','buzz'],
          'Filterbuzz';

my $events = Queue::Primary->new();

my @monday = (
    { day   => 'Monday',
      event => 'Walked the dog' },
    { day   => 'Monday',
      event => 'Fed the cat' },
    { day   => 'Monday',
      event => 'Milked the cow' },
);
my @tuesday = (
    { day   => 'Tuesday',
      event => 'Watered the horse' },
);

for my $event (@monday, @tuesday) {
    $events->push($event);
}

sub on {
    my $key = shift;
    return sub { $_[0]->{$key} eq $_[1]->{$key} };
}

my $grouped = $events->group( code => on('day') );
is_deeply [$grouped->toArray],
          [\@monday],
          'Grouping OK (for fully completed days)'
          or diag Dumper([$grouped->toArray], [$grouped->stack->toArray]);

my $new_tuesday = (
    { day   => 'Tuesday',
      event => 'Grassed up the rabbit' },
);
push @tuesday, $new_tuesday;
my $wednesday = (
    { day   => 'Wednesday',
      event => "Got on the goat's goat" },
);
for my $event ($new_tuesday, $wednesday) {
    $events->push($event);
}
$grouped->update;
is_deeply [$grouped->toArray],
          [\@monday, \@tuesday],
          'Grouping OK (for fully completed days, on update)'
          or diag Dumper([$grouped->toArray], [$grouped->stack->toArray]);

sub summarize {
    my @events = @{ +shift };
    return {
        day   => $events[0]->{day},
        count => scalar @events,
    };
}
my $summary = $grouped->map( code => \&summarize );

my $expected_summary = [
    {day=>'Monday',count=>3}, {day=>'Tuesday',count=>2}];

is_deeply [$summary->toArray],
          $expected_summary,
          'Summary of grouping';

my $direct_summary = $events
    ->group( code=>on('day'))
    ->map  ( code=>\&summarize);

is_deeply [$direct_summary->toArray],
          $expected_summary,
          'Multiple steps in one query';

done_testing;
