#!/usr/bin/env perl
use 5.020;
use warnings;
use strict;

use lib 'lib';
use LibUSB;
use LibUSB::USBTMC;

use Benchmark 'timethis';

my $driver = LibUSB::USBTMC->new(
    vid => 0x0957, pid => 0x0607,
    # debug_mode => 1, 
    # libusb_log_level => LIBUSB_LOG_LEVEL_DEBUG
    );

#$driver->write(data => "*RST\n");
$driver->write(data => "*CLS\n");
$driver->write(data => "VOLT:NPLC 0.006\n");

#timethis(1000, sub {print $driver->query(data => ":read?\n", length => 200);});
for my $i (1..100) {
    say $i;
    print $driver->query(data => "*IDN?\n", length => 200);
    print $driver->query(data => ":read?\n", length => 200);
}

# for (1..1000) {
#     $driver->write(data => ":read?");
#     print $driver->read(length => 100);
#     # $driver->write(data => "*IDN?\n");
#     # print "idn: ", $driver->read(length => 200);
# }
