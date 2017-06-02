use strict;
use warnings;
package LibUSB::USBTMC;

use LibUSB;
use Moose;
use MooseX::Params::Validate 'validated_list';


use constant {
    MsgID_DEV_DEP_MSG_OUT => 1,
    MsgID_REQUEST_DEV_DEP_MSG_IN => 2,
    MsgID_DEV_DEP_MSG_IN => 2,
    MsgID_VENDOR_SPECIFIC_OUT => 126,
    MsgID_REQUEST_VENDOR_SPECIFIC_IN => 127,
    MsgID_VENDOR_SPECIFIC_IN => 127,

    MESSAGE_FINALIZES_TRANSFER => "\x{01}",
    MESSAGE_DOES_NOT_FINALIZE_TRANSFER => "\x{00}",
};

my $null_byte = "\x{00}";

has 'vid' => (
    is => 'ro',
    isa => 'Int',
    required => 1
    );

has 'pid' => (
    is => 'ro',
    isa => 'Int',
    required => 1
    );

has 'ctx' => (
    is => 'ro',
    isa => 'LibUSB',
    init_arg => undef,
    writer => '_ctx',
    );

has 'device' => (
    is => 'ro',
    isa => 'LibUSB::Device',
    init_arg => undef,
    writer => '_device',
    );

has 'handle' => (
    is => 'ro',
    isa => 'LibUSB::Device::Handle',
    init_arg => undef,
    writer => '_handle',
    );

# Bulk endpoint addresses.
has 'bulk_out_endpoint' => (
    is => 'ro',
    isa => 'Int',
    init_arg => undef,
    writer => '_bulk_out_endpoint',
    );

has 'bulk_in_endpoint' => (
    is => 'ro',
    isa => 'Int',
    init_arg => undef,
    writer => '_bulk_in_endpoint',
    );

has 'btag' => (
    is => 'ro',
    isa => 'Int',
    init_arg => undef,
    writer => '_btag',
    default => 0,
    );


sub BUILD {
    my $self = shift;
    my $ctx = LibUSB->init();
    $ctx->set_debug(LIBUSB_LOG_LEVEL_WARNING);
    
    my $handle = $ctx->open_device_with_vid_pid($self->vid(), $self->pid());
    my $device = $handle->get_device();
    

    eval {
        $handle->set_auto_detach_kernel_driver(1);
    };

    # FIXME: is interface always 0. Search for USBTMC interface?

    $handle->claim_interface(0);
    
    $self->_ctx($ctx);
    $self->_device($device);
    $self->_handle($handle);

    $self->_get_endpoint_addresses();
}

sub _get_endpoint_addresses {
    my $self = shift;
    # FIXME: loop over endpoints. This is just for Agilent 34410A.
    $self->_bulk_out_endpoint(0x2);
    $self->_bulk_in_endpoint(0x86);
}

sub dev_dep_msg_out {
    my $self = shift;
    my ($data, $timeout) = validated_list(
        \@_,
        data => {isa => 'Str'},
        timeout => {isa => 'Int', default => 5000},
        );
    
    my $header = $self->_dev_dep_msg_out_header(length => length $data);
    my $endpoint = $self->bulk_out_endpoint();

    # Ensure that total number of bytes is multiple of 4.
    $data .= $null_byte x ((length $data) % 4); 
    $self->handle()->bulk_transfer_write($endpoint, $header . $data, $timeout);
}

sub request_dev_dep_msg_in {
    my $self = shift;
    my ($length, $timeout) = validated_list(
        \@_,
        length => {isa => 'Int', default => 1000},
        timeout => {isa => 'Int', default => 5000},
        );
    
    my $header = $self->_dev_dep_msg_in_header(length => $length);
    my $endpoint = $self->bulk_out_endpoint();

    # Length of $header is already multiple of 4.
    $self->handle()->bulk_transfer_write($endpoint, $header, $timeout);
}

sub _dev_dep_msg_out_header {
    my $self = shift;
    my ($length) = validated_list(\@_, length => {isa => 'Int'});
    
    my $header = $self->_bulk_out_header(MsgID => MsgID_DEV_DEP_MSG_OUT);
    $header .= pack('V', $length);
    $header .= MESSAGE_FINALIZES_TRANSFER;
    $header .= $null_byte x 3;  # Reserved bytes.
    return $header;
}

sub _request_dev_dep_msg_in_header {
    my $self = shift;
    my ($length) = validated_list(\@_, length => {isa => 'Int'});
    my $header = $self->_bulk_out_header(MsgID => MsgID_REQUEST_DEV_DEP_MSG_IN);
    $header .= pack('V', $length);
    $header .= pack('C', 2); # Fixme: make argument
    $header .= '\n';         # Term char
    $header .= $null_byte x 2; # Reserved. Must be 0x00.
    return $header;
}


sub _bulk_out_header {
    my $self = shift;
    my ($MsgID) = validated_list(\@_, MsgID => {isa => 'Int'});
    my $bulk_out_header = pack('C', $MsgID);
    my ($btag, $btag_inverse) = $self->_btags();
    $bulk_out_header .= $btag . $btag_inverse;

    $bulk_out_header .= $null_byte;    # Reserved. Must be 0x00;

    return $bulk_out_header;
}

sub _btags {
    my $self = shift;
    my $btag = $self->btag();
    $btag++;
    if ($btag == 256) {
        $btag = 1;
    }
    $self->_btag($btag);
    my $btag_inverse = ($btag ^ 0xff);
    return (pack('C', $btag), pack('C', $btag_inverse));
}

sub clear {
    my $self = shift;
    my ($timeout) = validated_list(
        \@_, timeout => {isa => 'Int', default => 5000});
    
    my $bmRequestType = 0xa1;   # See USBTMC 4.2.1.6 INITIATE_CLEAR
    my $bRequest = 5;
    my $wValue = 0;
    my $wIndex = 0; # FIXME: interface number
    return $self->handle()->control_transfer_read($bmRequestType, $bRequest, $wValue, $wIndex, 1, $timeout);
    
}

sub clear_halt_out {
    my $self = shift;
    my $endpoint = $self->bulk_out_endpoint();
    $self->handle()->clear_halt($endpoint);
}

sub clear_halt_in {
    my $self = shift;
    my $endpoint = $self->bulk_in_endpoint();
    $self->handle()->clear_halt($endpoint);
}

__PACKAGE__->meta->make_immutable();

1;
