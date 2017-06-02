#!/usr/bin/env perl
use 5.020;
use warnings;
use strict;
use lib 'lib';
use LibUSB;
use LibUSB::USBTMC;

my $driver = LibUSB::USBTMC->new(
    vid => 0x0957, pid => 0x0607,
    debug_mode => 0, 
    # libusb_log_level => LIBUSB_LOG_LEVEL_DEBUG
    );

$driver->write(data => "*CLS\n");
$driver->write(data => "*RST\n");
for (1..1000) {
    $driver->write(data => "*RST\n");
    # $driver->write(data => "*IDN?\n");
    # print "idn: ", $driver->read(length => 200);
}
