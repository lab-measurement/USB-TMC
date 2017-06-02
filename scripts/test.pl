#!/usr/bin/env perl
use 5.020;
use warnings;
use strict;
use lib 'lib';
use LibUSB;
use LibUSB::USBTMC;

my $driver = LibUSB::USBTMC->new(
    vid => 0x0957, pid => 0x0607,
    debug_mode => 1, 
    libusb_log_level => LIBUSB_LOG_LEVEL_DEBUG
    );

$driver->write(data => "*RST\n");
$driver->write(data => "*CLS\n");
$driver->write(data => ":read?\n");
$driver->request_dev_dep_msg_in(length => 200);
print $driver->dev_dep_msg_in(length => 200);

# $driver->write(data => ":read?\n");
# print $driver->read(length => 100);

# for (1..1000) {
#     $driver->write(data => ":read?");
#     print $driver->read(length => 100);
#     # $driver->write(data => "*IDN?\n");
#     # print "idn: ", $driver->read(length => 200);
# }
