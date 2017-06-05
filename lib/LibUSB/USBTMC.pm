use strict;
use warnings;
package LibUSB::USBTMC;

use LibUSB; # import the LIBUSB_* constants.
use LibUSB::Moo;
use Moose;
use MooseX::Params::Validate 'validated_list';
use Carp;

use constant {
    MSGID_DEV_DEP_MSG_OUT => 1,
    MSGID_REQUEST_DEV_DEP_MSG_IN => 2,
    MSGID_DEV_DEP_MSG_IN => 2,
    MSGID_VENDOR_SPECIFIC_OUT => 126,
    MSGID_REQUEST_VENDOR_SPECIFIC_IN => 127,
    MSGID_VENDOR_SPECIFIC_IN => 127,

    MESSAGE_FINALIZES_TRANSFER => "\x{01}",
    MESSAGE_DOES_NOT_FINALIZE_TRANSFER => "\x{00}",

    FEATURE_SELECTOR_ENDPOINT_HALT => 0,

    BULK_HEADER_LENGTH => 12,
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
    isa => 'LibUSB::Moo',
    init_arg => undef,
    writer => '_ctx',
    );

has 'device' => (
    is => 'ro',
    isa => 'LibUSB::Moo::Device',
    init_arg => undef,
    writer => '_device',
    );

has 'handle' => (
    is => 'ro',
    isa => 'LibUSB::Moo::Device::Handle',
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

has 'debug_mode' => (
    is => 'ro',
    isa => 'Bool',
    default => 0
    );

has 'libusb_log_level' => (
    is => 'ro',
    isa => 'Int',
    default => LIBUSB_LOG_LEVEL_WARNING,
    );

sub _debug {
    my $self = shift;
    if ($self->debug_mode()) {
        carp @_;
    }
}

sub BUILD {
    my $self = shift;
    my $ctx = LibUSB::Moo->init();
    $ctx->set_debug($self->libusb_log_level());

    # FIXME: use iSerial to search for device. Provide utility function in
    # LibUSB::Moo?
    my $handle = $ctx->open_device_with_vid_pid($self->vid(), $self->pid());

    # Clean up.
    $handle->reset_device();
    
    my $device = $handle->get_device();
    
    eval {
        # This will throw on windows and darwin. Catch exception with eval.
        $self->_debug("enable auto detatch of kernel driver.");
        $handle->set_auto_detach_kernel_driver(1);
    };
    
    
    # FIXME: is interface always 0? Search for USBTMC interface?

    $self->_debug("Claim USBTMC interface.");
    $handle->claim_interface(0);
    
    $self->_ctx($ctx);
    $self->_device($device);
    $self->_handle($handle);

    $self->_get_endpoint_addresses();

    $self->_debug(
        "Request clear_feature endpoint_halt for both bulk endpoints."
        );

    $self->clear_halt_out();
    $self->clear_halt_in();
    $self->clear_feature_endpoint_out();
    $self->clear_feature_endpoint_in();
}

sub _get_endpoint_addresses {
    my $self = shift;
    # FIXME: loop over endpoints. This is just for Agilent 34410A.
    $self->_bulk_out_endpoint(0x2);
    $self->_bulk_in_endpoint(0x86);
}

sub write {
    my $self = shift;
    return $self->dev_dep_msg_out(@_);
}

sub read {
    my $self = shift;
    my ($length, $timeout) = validated_list(
        \@_,
        length => {isa => 'Int'},
        timeout => {isa => 'Int', default => 5000}
        );
    $self->request_dev_dep_msg_in(length => $length, timeout => $timeout);
    return $self->dev_dep_msg_in(length => $length, timeout => $timeout);
}

sub dev_dep_msg_out {
    my $self = shift;
    my ($data, $timeout) = validated_list(
        \@_,
        data => {isa => 'Str'},
        timeout => {isa => 'Int', default => 5000},
        );
    
    $self->_debug("doing dev_dep_msg_out with data $data");
    
    my $header = $self->_dev_dep_msg_out_header(length => length $data);
    my $endpoint = $self->bulk_out_endpoint();

    # Ensure that total number of bytes is multiple of 4.
    $data .= $null_byte x ((4 - (length $data) % 4) % 4);
    $self->handle()->bulk_transfer_write($endpoint, $header . $data, $timeout);
}

sub dev_dep_msg_in {
    my $self = shift;
    my ($length, $timeout) = validated_list(
        \@_,
        length => {isa => 'Int'},
        timeout => {isa => 'Int', default => 5000}
        );
    
    $self->_debug("doing dev_dep_msg_in with length $length");
    
    my $endpoint = $self->bulk_in_endpoint();
    my $data = $self->handle()->bulk_transfer_read(
        $endpoint, $length + BULK_HEADER_LENGTH
        , $timeout
        );
    
    if (length $data < BULK_HEADER_LENGTH) {
        croak "dev_dep_msg_in does not contain header";
    }
    
    my $header = substr($data, 0, BULK_HEADER_LENGTH);
    $data = substr($data, BULK_HEADER_LENGTH);
    return $data;
}

sub request_dev_dep_msg_in {
    my $self = shift;
    my ($length, $timeout) = validated_list(
        \@_,
        length => {isa => 'Int', default => 1000},
        timeout => {isa => 'Int', default => 5000},
        );
    $self->_debug("doing request_dev_dep_msg_in with length $length");
    my $header = $self->_request_dev_dep_msg_in_header(length => $length);
    my $endpoint = $self->bulk_out_endpoint();

    # Length of $header is already multiple of 4.
    $self->handle()->bulk_transfer_write($endpoint, $header, $timeout);
}

sub _dev_dep_msg_out_header {
    my $self = shift;
    my ($length) = validated_list(\@_, length => {isa => 'Int'});
    
    my $header = $self->_bulk_out_header(MSGID => MSGID_DEV_DEP_MSG_OUT);
    $header .= pack('V', $length);
    $header .= MESSAGE_FINALIZES_TRANSFER;
    $header .= $null_byte x 3;  # Reserved bytes.
    return $header;
}

sub _request_dev_dep_msg_in_header {
    my $self = shift;
    my ($length) = validated_list(\@_, length => {isa => 'Int'});
    my $header = $self->_bulk_out_header(MSGID => MSGID_REQUEST_DEV_DEP_MSG_IN);
    # Transfer length
    $header .= pack('V', $length);
    # Term char enabled? 2 or 0. make argument
    $header .= pack('C', 2); # Fixme: make argument
    $header .= "\n";         # Term char
    $header .= $null_byte x 2; # Reserved. Must be 0x00.
    
    return $header;
}


sub _bulk_out_header {
    my $self = shift;
    my ($MSGID) = validated_list(\@_, MSGID => {isa => 'Int'});
    my $bulk_out_header = pack('C', $MSGID);
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
    # FIXME: check clear status in loop.
    
}

sub clear_feature_endpoint_out {
    my $self = shift;
    my ($timeout) = validated_list(
        \@_, timeout => {isa => 'Int', default => 5000});
    
    my $endpoint = $self->bulk_out_endpoint();
    my $bmRequestType = LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_STANDARD
        | LIBUSB_RECIPIENT_ENDPOINT;
    my $bRequest = LIBUSB_REQUEST_CLEAR_FEATURE;
    my $wValue = FEATURE_SELECTOR_ENDPOINT_HALT;
    my $wIndex = $endpoint;
    $self->handle()->control_transfer_write(
        $bmRequestType, $bRequest, $wValue, $wIndex, "", $timeout);
}

sub clear_feature_endpoint_in {
    my $self = shift;
    my ($timeout) = validated_list(
        \@_, timeout => {isa => 'Int', default => 5000});
    
    my $endpoint = $self->bulk_in_endpoint();
    my $bmRequestType = LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_STANDARD
        | LIBUSB_RECIPIENT_ENDPOINT;
    my $bRequest = LIBUSB_REQUEST_CLEAR_FEATURE;
    my $wValue = FEATURE_SELECTOR_ENDPOINT_HALT;
    my $wIndex = $endpoint;
    $self->handle()->control_transfer_write(
        $bmRequestType, $bRequest, $wValue, $wIndex, "", $timeout);
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

=head1 NAME

LibUSB::USBTMC - USB Test and Measurement Class (USBTMC) client driver

