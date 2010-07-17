package Harold::Event;
use KiokuDB::Class;
use Module::Pluggable sub_name => '_plugins';
use Module::Load;

has plugins => (
    traits => ['Hash'],
    is => 'rw',
    isa => 'HashRef[Str]',
    lazy_build => 1,
    handles => {
        get_plugin => 'get',
    },
);

sub raise {
    my ($self, $type, @params) = @_;
    my $class = $self->get_plugin($type) or die "No such type $type";
    load $class;
    return $class->new( @params );
}

sub _build_plugins {
    my $self = shift;
    my $pkg = ref $self;
    $self->search_path( new => $pkg );
    return {
        map {
            /^${pkg}::(.*)$/ => $_,
        } $self->_plugins
    };
}

1;
