package Device::SDS011;

# Last updated September 14, 2019
#
# Author:       Irakliy Sunguryan ( www.sochi-travel.info )
# Date Created: September 14, 2019

use strict;
use warnings;
use feature 'say';

use vars qw($VERSION);
$VERSION    = '0.01';

use Device::SerialPort;
use List::Util 'sum';

$| = 1;

# =======================================================

sub hex_print_str {
    my $str = shift;
    my $ret_str;
    my $len = length($str) - 1;
    for my $i (0..$len) {
        my $char = substr $str, $i, 1;
        $ret_str .= sprintf("%02X ", ord($char));
    }
    $ret_str // chop($ret_str);
    return $ret_str;
}

# =======================================================

use constant {
    MSG_TAIL => "\xAB",
    MODE_SLEEP => 0,
    MODE_WORK  => 1,
    REQ_TEMPLATE => [0xAA,0xB4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF,0xFF,0x00,0xAB],
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
    
    $self->{port}->are_match(MSG_TAIL);
    
    bless $self, $class;
    return $self;
}

sub _checksum {
    my @data_bytes = @_; # exactly 15 bytes
    return sum(@data_bytes) % 256;
}

sub _write_serial {
    my $self = shift;
    my $bytes = shift;
    my $str = pack('C*', @$bytes);
        say "Writing: ".hex_print_str($str). " / Length: ".length($str);
    $self->{port}->lookclear;
    my $count_out = $self->{port}->write($str);
        say "count_out = $count_out";
        warn "write failed\n"      unless  $count_out;
        warn "write incomplete\n"  if  $count_out != length($str);
    return $count_out;
}

sub _read_serial {
    my $self = shift;
    #$self->{port}->lookclear;
    my $ret;
    while(1) {
        my $str = $self->{port}->lookfor;
            # looks for are_match() 
            # and returns data UP TO the match (exluding it)
        # say hex_print_str($str) if $str;
        $ret = $str, last if $str && length($str) == 9;
    }
    $self->{port}->lookclear;
        say "Read: ".hex_print_str($ret);
    return $ret;
}

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

sub sensor_mode {
    my $self = shift;
    my $mode = shift;
    if (defined($mode)) {
        # set mode
        my @out = @{REQ_TEMPLATE()};
        $out[2] = 6;      # Data byte 1 = 6
        $out[3] = 1;      # Data byte 2: 0=query, 1=set
        $out[4] = $mode;  # Data byte 3: MODE_SLEEP or MODE_WORK
        $out[17] = _checksum(@out[2..16]);
        $self->_write_serial(\@out);
        my $response = $self->_read_serial();
        return $response;
    } else {
        # query current mode
    }
    return 0;
}

sub working_period {
    my $self = shift;
    my $minutes = shift;
    return 0;
}

sub firmware {
    my $self = shift;
    my @out = @{REQ_TEMPLATE()};
    $out[2] = 7; # Data byte 1
    $out[17] = _checksum(@out[2..16]);
    $self->_write_serial(\@out);
    my $response = $self->_read_serial();
    return $response;
}

1;