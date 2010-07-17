use strict;
use warnings;
use inc::Module::Install 0.77;

name 'Harold';
all_from 'lib/Harold.pm';

requires "Moose" => "0.64";
requires "namespace::clean";
requires "Test::More";
requires "Data::Dumper";
requires "Scalar::Util";
requires "KiokuDB";
requires "Module::Runtime";
requires "SQL::Translator"; # for deploy of DBIC backend
requires "Module::Pluggable";
requires "XML::Atom";
requires "MooseX::Types::DateTime";

WriteAll();
