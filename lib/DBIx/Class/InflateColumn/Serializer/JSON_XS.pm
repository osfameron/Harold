package DBIx::Class::InflateColumn::Serializer::JSON_XS;
 
 
use strict;
use warnings;
use JSON::XS;
use Carp;


{
    my $json;
    sub _json {
        $json //= JSON::XS->new->convert_blessed(1)->allow_blessed(1)->allow_nonref(1);
    }
}
 
 
sub get_freezer{
  my ($class, $column, $info, $args) = @_;
 
  if (defined $info->{'size'}){
      my $size = $info->{'size'};
      return sub {
        my $s = __PACKAGE__->_json->encode(shift);
        croak "serialization too big" if (length($s) > $size);
        return $s;
      };
  } else {
      return sub {
        return __PACKAGE__->_json->encode(shift);
      };
  }
}
 
 
sub get_unfreezer {
  return sub {
    return __PACKAGE__->_json->decode(shift);
  };
}
 
 
1;
