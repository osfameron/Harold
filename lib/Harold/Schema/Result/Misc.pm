package Harold::Schema::Result::Misc;

use parent 'DBIx::Class::Core';

__PACKAGE__->load_components(qw/ /);

__PACKAGE__->table('raw');

__PACKAGE__->add_columns(
    id => {
        data_type         => 'integer',
        size              => 16,
        is_nullable       => 0,
        is_auto_increment => 1,
    },
    event_id => {
        data_type         => 'integer',
        size              => 16,
        is_nullable       => 0,
    },
    queue_id => {
        data_type         => 'integer',
        size              => 16,
        is_nullable       => 0,
    },
    event_type => {
        data_type   => 'varchar',
        size        => 255,
        is_nullable => 0,
    },
    event_created => {
        data_type     => 'datetime',
        is_nullable => 0,
    },
    json => {
        data_type   => 'text',
        is_nullable => 0,
    },
);

__PACKAGE__->set_primary_key('id');

1;
