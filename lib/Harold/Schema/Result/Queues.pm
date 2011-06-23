package Harold::Schema::Result::Queues;

use parent 'DBIx::Class::Core';

__PACKAGE__->load_components(qw/ /);

__PACKAGE__->table('queues');

__PACKAGE__->add_columns(
    queue_id => {
        data_type         => 'integer',
        size              => 16,
        is_nullable       => 0,
        is_auto_increment => 1,
    },
    name => {
        data_type   => 'varchar',
        size        => 255,
        is_nullable => 0,
    },
    tablesource => {
        data_type   => 'varchar',
        size        => 255,
        is_nullable => 0,
    },
    from_queue_id => {
        data_type   => 'integer',
        size        => 16,
        is_nullable => 1,
    },
    pos => {
        data_type   => 'integer',
        size        => 16,
        is_nullable => 1,
    },
    codestring => {
        data_type   => 'text',
        is_nullable => 1,
    },
);

__PACKAGE__->set_primary_key('queue_id');
# __PACKAGE__->add_unique_constraint(['name']);

# __PACKAGE__->belongs_to( from => __PACKAGE__, { 'foreign.queue_id' => 'self.from_queue_id'}, { join_type => 'left' });

1;
