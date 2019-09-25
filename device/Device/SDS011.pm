package Device::SDS011;

# Last updated September 25, 2019
#
# Author:       Irakliy Sunguryan ( www.sochi-travel.info )
# Date Created: September 25, 2019

##############################################################################
# NOTE 1: All functions will save/update the Device ID, 
#         sice all commands return it anyway.
##############################################################################

use v5.10; # for "Defined OR" operator
use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.01';

use Device::SerialPort; 
use List::Util 'sum';

# =======================================================

use constant {
    CMD_DATA => "\xC0",
    CMD_REPLY => "\xC5",
    MODE_SLEEP => 0,
    MODE_WORK  => 1,
    #---
    REQ_TEMPLATE => [
        0xAA,0xB4,0x00,      # header, command, instruction
        0x00,0x00,0x00,0x00, # data
        0x00,0x00,0x00,0x00,
        0x00,0x00,0x00,0x00,
        0xFF,0xFF,0x00,0xAB, # device id, checksum, tail
    ],
    #---
    CMD_BYTE_REPORTING_MODE => 2,
    CMD_BYTE_QUERY_DATA => 4,
    CMD_BYTE_DEVICE_ID => 5,
    CMD_BYTE_SLEEP_WORK => 6,
    CMD_BYTE_WORKING_PERIOD => 8,
    CMD_BYTE_FIRMWARE => 7,
    #---
    MAX_MSGS_READ => 10,
        # when sensor is in "continuous" working mode (default),
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
    
    $self->{port}->write_settings || undef $self->{port};
    
    bless $self, $class;
    return $self;
}

sub _checksum {
    my @data_bytes = @_;
    return sum(@data_bytes) % 256;
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
            $msg .= $byte;
            $msg = substr($msg,-10);
            if (length($msg) == 10 
                && substr($msg,0,1) eq "\xAA"
                && substr($msg,-1)  eq "\xAB")
            {
                $readMessages++;
                last unless $cmdChar;
                last if $readMessages >= MAX_MSGS_READ; # give up after this many messages
                last if $cmdChar && substr($msg,1,1) eq $cmdChar;
            }
        }
    }
    $msg = undef  if $cmdChar && substr($msg,1,1) ne $cmdChar;
    return $msg;
}

sub _write_serial {
    my $self = shift;
    my $bytes = shift;
    my $str = pack('C*', @$bytes);
    $self->{port}->lookclear;
    my $count_out = $self->{port}->write($str);
    # $self->{port}->write_drain;
        warn "write failed\n"      unless  $count_out;
        warn "write incomplete\n"  if  $count_out != length($str);
    return $count_out;
}

# ACCEPTS: (1) [required] array ref of 15 data bytes (intergers)
#          (2) [optional] flag of whether to expect \xC0 reply (sensor data), 
#                         which is only for data query command
# RETURNS: a response (string of bytes)
sub _write_msg {
    my $self = shift;
    my ($data, $expect_sensor_data) = @_;
    my @out = @{REQ_TEMPLATE()};
    $out[$_+2] = $data->[$_] for 0..14;
    $out[17] = _checksum(@out[2..16]);
    $self->_write_serial(\@out);
    return $self->_read_serial(($expect_sensor_data ? undef : CMD_REPLY));
}

sub _update_device_id {
    my $self = shift;
    my $msg = shift; # full response message
    if (!$self->{_device_id}) {
        my @deviceId = map { ord } split //, substr($msg,6,2);
        $self->{_device_id} = \@deviceId;
    }
}

# ---------------------------------------------------------------------------

##############################################################################
# RETURNS: Array ref of calculated sensor values: [PM25, PM10]
##############################################################################
sub live_data {
    my $self = shift;
    my $response = $self->_read_serial;
    my @values = map { ord } split //, $response;
    return [
        (($values[3] * 256) + $values[2]) / 10,
        (($values[5] * 256) + $values[4]) / 10,
    ];
}

sub query_data {
    my $self = shift;
    my @out = @{REQ_TEMPLATE()}[2..16];
    my $response = $self->_write_msg([CMD_BYTE_QUERY_DATA, @{REQ_TEMPLATE()}[3..16]], 1);
    $self->_update_device_id($response);
    my @values = map { ord } split //, $response;
    return [
        (($values[3] * 256) + $values[2]) / 10,
        (($values[5] * 256) + $values[4]) / 10,
    ];
}

sub _change_mode {
    my $self = shift;
    my ($mode_type, $mode_value) = @_;
    my @out = @{REQ_TEMPLATE()}[2..16];
    $out[0] = $mode_type;
        # CMD_BYTE_REPORTING_MODE, CMD_BYTE_SLEEP_WORK, CMD_BYTE_WORKING_PERIOD
    ($out[1], $out[2]) = defined($mode_value) ? (1,$mode_value) : (0,0);
    my $response = $self->_write_msg(\@out);
    $self->_update_device_id($response) if $response;
    return ($response ? ord(substr($response,4,1)) : undef);
}

##############################################################################
# ACCEPTS: OPTIONAL Mode to set: 0=Report active mode, 1=Report query mode
# RETURNS: Current reporting mode
##############################################################################
sub reporting_mode {
    my $self = shift;
    my $mode = shift;
    return $self->_change_mode(CMD_BYTE_REPORTING_MODE, $mode);
}

##############################################################################
# ACCEPTS: OPTIONAL Mode to set: 0=Sleep, 1=Work
# RETURNS: Current mode
##############################################################################
sub sensor_mode {
    my $self = shift;
    my $mode = shift;
    return $self->_change_mode(CMD_BYTE_SLEEP_WORK, $mode);
}

##############################################################################
# ACCEPTS: OPTIONAL Mode/Period in minutes to set: 
#          0=continuous mode, 1-30 minutes (work 30 seconds and sleep n*60-30 seconds)
# RETURNS: Current mode/Period in minutes
##############################################################################
sub working_period {
    my $self = shift;
    my $minutes = shift;
    return $self->_change_mode(CMD_BYTE_WORKING_PERIOD, $minutes);
}

##############################################################################
# RETURNS: Array ref [year, month, day] of the firmware version
# NOTE: This will only read the value from the device if it wasn't read before
##############################################################################
sub firmware {
    my $self = shift;
    if (!$self->{_firmware_verion}) {
        my $response = $self->_write_msg([CMD_BYTE_FIRMWARE, @{REQ_TEMPLATE()}[3..16]]);
        if (defined $response) {
            my @version = map { ord } split //, substr($response,3,3);
                # Firmware version byte 1: year
                # Firmware version byte 2: month
                # Firmware version byte 3: day
            $self->{_firmware_verion} = \@version;
            $self->_update_device_id($response);
        }
    }
    # TODO: question: if it was successfully read on previous call 
    # and the $self->{_firmware_verion} is set, should I undef it in case this read fails?
    return $self->{_firmware_verion};
}

sub device_id {
    my $self = shift;
    my @new_id = @_; # 2 bytes (integers)
    if (@new_id) {
        my @out = @{REQ_TEMPLATE()}[2..16];
        $out[0] = CMD_BYTE_DEVICE_ID;
        ($out[11], $out[12]) = @new_id;
        my $response = $self->_write_msg(\@out);
        $self->_update_device_id($response);
    }
    else {
        # (ab)use reporing mode function to read and update the ID
        $self->reporting_mode if (!$self->{_device_id});
    }
    return $self->{_device_id};
}

sub done {
    my $self = shift;
    undef $self->{port};
}

sub DESTROY {
    my $self = shift;
    undef $self->{port} if $self->{port};
}

1;