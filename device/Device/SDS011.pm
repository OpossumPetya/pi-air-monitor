package Device::SDS011;

# Last updated September 14, 2019
#
# Author:       Irakliy Sunguryan ( www.sochi-travel.info )
# Date Created: September 14, 2019

use strict;
use warnings;
use feature 'say';
use Data::Printer;

use vars qw($VERSION);
$VERSION    = '0.01';

use Device::SerialPort qw( :PARAM :STAT 0.07 ); 
use List::Util 'sum';

$| = 1;

# =======================================================

sub trim {
    (my $s = $_[0]) =~ s/^\s+|\s+$//g;
    return $s;
}

sub hex_print_str {
    my $str = shift;
    my $ret_str;
    my $len = length($str) - 1;
    for my $i (0..$len) {
        my $char = substr $str, $i, 1;
        $ret_str .= sprintf("%02X ", ord($char));
    }
    return $ret_str;
}

# =======================================================

use constant {
    MSG_TAIL => "\xAB",
    CMD_DATA => "\xC0",
    CMD_REPLY => "\xC5",
    MODE_SLEEP => 0,
    MODE_WORK  => 1,
    REQ_TEMPLATE => [0xAA,0xB4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF,0xFF,0x00,0xAB],
    #---
    CMD_BYTE_REPORTING_MODE => 2,
    CMD_BYTE_QUERY_DATA => 4,
    CMD_BYTE_DEVICE_ID => 5,
    CMD_BYTE_SLEEP_WORK => 6,
    CMD_BYTE_WORKING_PERIOD => 8,
    CMD_BYTE_FIRMWARE => 7,
    #---
    MAX_MSGS_READ => 10,
        # when sensor is in "continuous" (default) working mode,
        # several data reading messages can appear before actual response to a command.
};

sub new {
    my $class = shift;
    my $serial_port = shift;

    my $self = {
        _device_id       => undef,
        _reporting_mode  => undef,
        _operation_mode  => undef,
        _working_period  => undef,
        _firmware_verion => undef,
    };

    $self->{port} = Device::SerialPort->new($serial_port);

    # The UART communication protocol：
    #  bit rate：   9600
    #  data bit：   8
    #  parity bit： NO
    #  stop bit：   1

    $self->{port}->baudrate(9600);
    $self->{port}->databits(8);
    $self->{port}->parity('none');
    $self->{port}->stopbits(1);
    
    # $self->{port}->binary;
    $self->{port}->write_settings || undef $self->{port};
    
    # $self->{port}->are_match(MSG_TAIL);
    
    bless $self, $class;
    return $self;
}

sub _checksum {
    my @data_bytes = @_;
    return sum(@data_bytes) % 256;
}

sub _write_serial {
    my $self = shift;
    my $bytes = shift;
    my $str = pack('C*', @$bytes); # ."\015";
        # say "Writing: ".hex_print_str($str);
    $self->{port}->lookclear;
    my $count_out = $self->{port}->write($str);
    # $self->{port}->write_drain;
        # say "count_out = $count_out";
        warn "write failed\n"      unless  $count_out;
        warn "write incomplete\n"  if  $count_out != length($str);
    return $count_out;
}

sub _read_serial {
    my $self = shift;
    my $cmdChar = shift; # C0 - sensor data; C5 - reply
    my $msg = '';
    my $readMessages = 0;
    $self->{port}->lookclear;
    while(1) {
        my $byte = $self->{port}->read(1);
        if ($byte) {
            # print hex_print_str($byte);
            $msg .= $byte;
            $msg = substr($msg,-10);
            if (length($msg) == 10 
                && substr($msg,0,1) eq "\xAA"
                && substr($msg,-1)  eq "\xAB")
            {
                $readMessages++;
                # say "[$readMessages]";
                last unless $cmdChar;
                last if $readMessages >= MAX_MSGS_READ; # give up after this many messages
                last if $cmdChar && substr($msg,1,1) eq $cmdChar;
            }
        }
    }
    # say "[".hex_print_str($msg).']';
    $msg = undef  if $cmdChar && substr($msg,1,1) ne $cmdChar;
    return $msg;
}

sub _update_device_id {
    my $self = shift;
    my $msg = shift; # full response message
    if (!$self->{_device_id}) {
        my @deviceId = map { ord } split //, substr($msg,6,2);
        $self->{_device_id} = \@deviceId;
        # say "\nDevice ID: ".hex_print_str(chr($deviceId[0])).' '.hex_print_str(chr($deviceId[1]));
    }
}

# ---------------------------------------------------------------------------

sub reporting_mode {
    my $self = shift;
    my ($mode, $minutes) = @_;
    return 0;
}

sub live_data {
    my $self = shift;
    my $response = $self->_read_serial();
    return $response;
}

sub query_data {
    my $self = shift;
    my $sensor_id = shift;
    return 0;
}

sub device_id {
    my $self = shift;
    my $id = shift;
    return 0;
}

##############################################################################
# ACCEPTS: Mode: 0=Sleep, 1=Work
# RETURNS: Current mode
# NOTE: This will also set the Device ID, as it's is also returned from the device,
#       but the function will not return it.
##############################################################################
sub sensor_mode {
    my $self = shift;
    my $mode = shift;
    say $mode if defined $mode;
    my @out = @{REQ_TEMPLATE()};
    $out[2] = CMD_BYTE_SLEEP_WORK;
    if (defined $mode) {
        $out[3] = 1; # 0=query, 1=set
        $out[4] = $mode;
    } else {
        $out[3] = 0;
    }
    $out[17] = _checksum(@out[2..16]);
    $self->_write_serial(\@out);
    my $response = $self->_read_serial(CMD_REPLY);
        # say "Read: ".hex_print_str($response) if $response;
    $self->_update_device_id($response);
    return ord(substr($response,4,1));
}

##############################################################################
##############################################################################
sub working_period {
    my $self = shift;
    my $minutes = shift;
    return 0;
}

##############################################################################
# RETURNS: Array ref [year, month, day] of the firmware version
# NOTE 1: This will only read the value from the device if it wasn't read before
# NOTE 2: This will also set the Device ID, as it's is also returned from the device,
#         but the function will not return it.
##############################################################################
sub firmware {
    my $self = shift;
    if (!$self->{_firmware_verion}) {
        my @out = @{REQ_TEMPLATE()};
        $out[2] = CMD_BYTE_FIRMWARE;
        $out[17] = _checksum(@out[2..16]);
        $self->_write_serial(\@out);
        my $response = $self->_read_serial(CMD_REPLY);
        if (defined $response) {
            my @version = map { ord } split //, substr($response,3,3);
                # Firmware version byte 1: year
                # Firmware version byte 2: month
                # Firmware version byte 3: day
                # say "\n$version[0]-$version[1]-$version[2]";
            $self->{_firmware_verion} = \@version;
            $self->_update_device_id($response);
        }
        # say 'Response is '.( $response ? '' : 'not ' ).'set';
    }
    # TODO: question: if it was successfully read on previous call 
    # and the $self->{_firmware_verion} is set, should I undef it in case this read fails?
    return $self->{_firmware_verion};
}

1;