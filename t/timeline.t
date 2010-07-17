#!/usr/bin/perl
use strict; use warnings;

use Test::More;

use Harold::List;
use PerlX::MethodCallWithBlock;

use Data::Dumper;
local $Data::Dumper::Indent = 1;
local $Data::Dumper::Maxdepth = 2;

use Harold::Timeline;
use DateTime;

# dummy modules for things we want to run feeds about
use lib 't/lib';
use Foo::Event;
use User;
use Module;

# Deps: KiokuDB, SQL::Translator (for deploy)
use KiokuDB;

{
    my @modules = map { Module->new(id=>$_) } 1..10;
    my @users   = map { User  ->new(id=>$_) } 1..10;

    my $events = Foo::Event->new;
    sub make_event {
        my $date = shift || DateTime->now;

        my $event = $events->raise(
            (rand > 0.5) ? 
                ( 'Completed' =>
                    object => int(rand(100)) )
              : ( 'Started' ),
                    datestamp => $date,
                    user      => $users[ int(rand(10)) ],
                    subject   => $modules[ int(rand(10)) ],
        );
    }
    sub make_event_list {
        my $date = shift || DateTime->now;
        return Harold::List->node(  
            make_event($date),
            sub { make_event_list($date->clone->subtract( days => 1)) }
            );
    }
}

{

    # my $kioku = KiokuDB->connect("dbi:mysql:dbname=kioku;user=root;password=password", create => $create);
    my $kioku = KiokuDB->connect("hash");

    my $scope = $kioku->new_scope;

    CREATE: {
        my $list = make_event_list()->take(40); 

        my $root_list = Harold::Timeline->create( 
            $kioku,
            list => $list, 
            store_as => 'root' );

        my $completions = Harold::Timeline->create(
            $kioku,
            store_as => 'completions',
            from_feed => 'root',
            make_list => sub {
                my $root = shift;
                $root->grep { $_[0]->isa('Foo::Event::Completed') };
            },
        );

        my $high_score = Harold::Timeline->create(
            $kioku,
            store_as => 'high_score',
            from_feed => 'completions',
            make_list => sub {
                my $completions = shift;
                $completions->grep { $_[0]->object >= 80 } };
            }
        );
    }

    my $root_list = $kioku->lookup( 'root' );
    my $h2        = $kioku->lookup( 'high_score' );
    diag Dumper( [ $h2->list->take(2)->to_array ] );

    # now, let's add some more events

    for (1..10) {
        $root_list->add_event( make_event() );
    }
    $h2->update($kioku);

    my $h3 = $kioku->lookup( 'high_score' );
    diag Dumper( [ $h3->list->take(5)->to_array ] ); # may be different from above

    diag "TODO: turn this into a proper test";
}
