package BarDB::Result::Dvd;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

BarDB::Result::Dvd

=cut

__PACKAGE__->table("dvds");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 1
  size: 32

=head2 user_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_nullable => 0 },
  "name",
  { data_type => "varchar", is_nullable => 1, size => 32 },
  "user_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 user

Type: belongs_to

Related object: L<BarDB::Result::User>

=cut

__PACKAGE__->belongs_to(
  "user",
  "BarDB::Result::User",
  { id => "user_id" },
  { join_type => "LEFT", on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 ratings

Type: has_many

Related object: L<BarDB::Result::Rating>

=cut

__PACKAGE__->has_many(
  "ratings",
  "BarDB::Result::Rating",
  { "foreign.dvd_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2010-07-18 23:54:03
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:j7bTwUcMs80uWbSu72QRKA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
