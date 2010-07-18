package Harold;
use KiokuDB::Class;

our $VERSION = '0.01';

=head1 NAME

Harold - a persistent event bus

=head1 SYNOPSIS

 use Harold::Timeline;
 use MyApp::Event;
 use PerlX::MethodCallWithBlock;

 use KiokuDB;
 {
    my $dir = KiokuDB->connect(...); my $scope = $dir->new_scope;

    my $root = Harold::Timeline->create( $dir, 
        store_as => 'root' );

    my $filter = Harold::Timeline->create( $dir,
        store_as => 'user_moves',
        from_feed => 'root',
        make_list => sub {
            my $root = shift;
            $root->grep { $_[0]->isa ('MyApp::Event::UserMove') };
        });

    my $event = MyApp::Event->new;

Later in code ...

    $root->add_event( 
        $event->raise( UserMove => 
            user => $user, # objects
            from => $from_team,
            to   => $to_team
            ));

    $root->add_event( 
        $event->raise( SomeOtherEvent => 
            some_obj   => $foo,
            ));

And to report ...

    my $user_moves = $dir->lookup('user_moves');
    $user_moves->update($dir); # bring filter up to date

    warn map { $_->as_xml } $filter->take(10)->to_array;

 } # end kioku scope

=head1 DESCRIPTION (bit of a ramble, really)

I<Once, when asked what represented the greatest challenge for a statesman,
British Prime Minister Harold Macmillan responded in his typically languid
fashion, "Events, my dear boy, events."> [1]

Guy came up with a cool idea for our app's front-page: to show anonymised
information from all the live instances. Things like

 * A manager assigned a survey to 135 users in a Retail location
 * 34 users completed a quiz in a Call-centre location
 * We upgraded the app for a telephony customer to version 1.2.3

If this could be running from fresh, realtime information, and nicely
aggregated it would give us, as well potential and existing customers an idea
about the level of usage.

It also ties in very nicely with some ideas we've been having about message
queues, notifications, and reporting. At the core of that is the idea of
recording every "event". For example:

 * user X finished quiz Y with a score of 67% on first attempt
 * admin Z assigned quix A to users B,C,D,E in department F
 * manager G ran a report on location H
 * team leader T reset password for user U
 * admin Z moved 5 users to team V

We could do various things with this information:

 * create feeds (anonymised or not, at various levels of detail) for a whole
   application instance, or a department, or a given user
 * trigger workflow: for example, passing a certain module at 80%+ might cause
   a congratulation email to be sent
 * sum up all the scores for a certain module to run a report on it.

=head2 First thoughts for implementation

My first thought was a message queue - but I don't think that's appropriate, as
message queues aren't persistent. But what I do want is something similar to
what Trelane developed at, um, "a digital media company": a database of events,
which can get processed by various agents. The design I remember was a large
SQL table, with serialized objects (Perl's Storable blobs, possibly) from which
other agents would progressively filter data into other, more focused, tables.

That was very cool. And it supports new queries easily - you just get them to
run through all of the database, starting at the beginning...

And here, I had a doubt: what if I want to be able to do ad-hoc queries. For
example, drilling down:

 * All events
  * Quiz completions
   * For location X
    * For department Y
     * For team Z
      * for user A

Up to team level, we might want to cache all this data. But really, for a
single user's home-page view of "recent stuff", we might only want the last 10
items' worth of data. Processing everything from the beginning feels like
overkill. Or at least inelegant.

=head2 Harold

What I came up with instead is something like the data structure for git -
where we can store streams of data but starting with the most recent rather
than the earliest.

So for example, I might have a 'root' list, which is the stream of events, and
then attach a set of transforms (maps and greps) to it.

In the example above, I'd simply attach a grep from all events for ones that
match completion, and so on.

Now that's a nice idea. But luckily it turns out nothingmuch's L<KiokuDB>
library makes it actually possible. KiokuDB is an "object graph" (I think
similar to AllegroCache in Lisp, and Haskell's persistance libraries in
HappStack or Yesod).

=head3 Laziness

You can tell Kioku to only bring references to other objects when they're
requested. This means I can have a linked list of 1000s of entries, without
pulling the whole list into memory ;-)

=head3 Closures work

I used this for the actual lazy lists. i.e. tail can hold a function-ref
"promise" instead of a List. That's a bit of a hack, as the modules available
for lazy data in Perl are mostly problematic in various ways, and I wasn't
certain if/how to use them with Kioku.

It also means that I can set a list to be

 $root->Grep { $_[0]->action eq 'completed' };

and have that block persisted neatly. This is very cool (and much neater than
what I had feared I'd have to do: create a set of Functor classes for each Map
or Grep transform).

=head3 I don't have to create new tables

This approach seems very flexible, as I can create new filters, and even
transforms without having to worry about defining and creating a new table to
put them in.

=head3 Can store L<DBIx::Class>objects

Apparently Kioku can store database rows using the popular DBIC object
relational mapper. I believe it stores ids rather than the row data, and they
are transparently inflated. That's very very cool, though for auditing
purposes, I'm wondering if I should store the serialized DB objects instead.

=head3 What about new events?

Of course, as my linked list goes backwards in time, you might ask what do I do
with new events? These get updated in a similar way to git commits! i.e. they
become the new HEAD, pointing back at the old list. The Feed object does a bit
of accounting and manipulation behind the scenes to make sure that Map/Grep'd
streams point to the previously calculated tail, instead of recalculating
everything.

(Derived streams can either be stored, in which case presumably we'll update
them at intervals to follow along with the root stream, or they can just run in
memory, if we're only interested in the most recent events).

=head3 Next steps

As I'm playing with lazy lists, I've implemented the minimum of list functions
stolen from haskell's prelude - C<map>, C<grep>, C<take>, C<takeWhile>,
C<foldl> and C<foldr>. But of course I'll want to summarize data too. For which
I think I'll need C<scanl> and C<scanr>, and various C<groupBy> functions.
Because this stream is based on lazy lists, I can reuse lots of existing
knowledge.

=head1 SEE ALSO

=over 4

=item *
[1] Never Had It So Good: A History of Britain from Suez to the Beatles by Dominic Sandbrook 
L<http://www.hoover.org/publications/policy-review/article/7427>

=item *
L<KiokuDB>

=item *
L<DBIx::Class>

=item *
L<PerlX::MethodCallWithBlock>

=item *
t/timeline.t

=back

=head1 AUTHOR and COPYRIGHT

 (C) osfameron@cpan.org 2010

=cut

1;
