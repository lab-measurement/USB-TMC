#!/usr/bin/env perl
use 5.020;
use warnings;
use strict;
use lib 'lib';
use LibUSB::TMC;

my $driver = LibUSB::TMC->new(vid => 0x0957, pid => 0x0607);

$driver->clear_halt_in();
$driver->clear_halt_out();

$driver->dev_dep_msg_out(data => "*RST\n");
$driver->dev_dep_msg_out(data => "VOLT:RANGE 10\n");

