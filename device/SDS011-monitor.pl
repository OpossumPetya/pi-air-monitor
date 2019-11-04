use v5.10;
use strict;
use warnings;

use lib '.';
use Device::SDS011;
use RPi::PIGPIO;
use RPi::PIGPIO::Device::DHT22;
use DateTime;
# For 'local' DateTime time zones ensure Linux's time zone is correctly configured first

$| = 1;

''//' --- FLOW: --------------------------------------------------------------
1. Ensure following Sensor settings are set:
    Reporting Mode: 1=Report query mode (is reset after sensor restart?)
    working_period: 0=continuous mode (is reset after sensor restart?)
2. Loop
    - get humidity
    - if humidity < 70%
    -   wake up: sensor_mode = 1/Work
    -   wait 10 seconds to warm up
    -   read values / get avergave of 3-5 readings
    -   send values
    - else if humidity > 90%
    -   send warning to the creator: datetime, humidity, 
             reminder that storage humidity should be less then 90%
    - sleep: sensor_mode = 0/Sleep,
    - wait 30 minutes
'; # -------------------------------------------------------------------------

use constant {
    AVG_OF => 3,
};

my $sensor = Device::SDS011->new('/dev/ttyUSB0');
my $pi = RPi::PIGPIO->connect('127.0.0.1');
my $dht22 = RPi::PIGPIO::Device::DHT22->new($pi,4);
    # "4" here is BCM 4 (GPCLK0) pin, pin #7

# -----------------------------------------------------

sub temp_humid {
    $dht22->trigger();
    return ($dht22->temperature, $dht22->humidity);
}

sub save_data {
    my ($dt, $temp, $humidity, $pm25, $pm10) = @_;
    $pm25 //= '';
    $pm10 //= '';
    open my $fh, '>>', './output/data.txt' or die "could not open file to save data";
    say $fh "$dt,$temp,$humidity,$pm25,$pm10";
    close $fh;
}

sub LOG {
    my $str = shift;
    say DateTime->now(time_zone => 'local')->strftime('%m-%d %H:%M:%S').'  '.$str;
}

#-------

$sensor->sensor_mode(1);    # wake up if sleeping
sleep 5;
$sensor->reporting_mode(1); # 1=Report query mode
$sensor->working_period(0); # 0=continuous mode

LOG("starting the loop!");
while (1) {
    my ($dt, $temp, $humidity, $pm25, $pm10)
        = (DateTime->now(time_zone => 'local'), (temp_humid()), undef, undef);
    LOG("loop: DT:[$dt], TEMP:[$temp] HUMID:[$humidity]");
    if ( $humidity < 70) {
        LOG("lets wake up - try 1...");
        $sensor->sensor_mode(1); # wake up
        sleep 10;                # warming up...
        LOG("lets wake up - try 2...");
        $sensor->sensor_mode(1);
        sleep 10;
        LOG("get a few data readings...");
        for (1..AVG_OF) {
            my ($p25_tmp,$p10_tmp) = @{$sensor->query_data};
            LOG("    Read: PM25:$p25_tmp, PM10:$p10_tmp");
            $pm25 += $p25_tmp;
            $pm10 += $p10_tmp;
            sleep 3;
        }
        $pm25 = sprintf("%.2f", $pm25/AVG_OF);
        $pm10 = sprintf("%.2f", $pm10/AVG_OF);
        LOG("here are my final values: PM25:$pm25, PM10:$pm10");
        save_data($dt, $temp, $humidity, $pm25, $pm10);
        $sensor->sensor_mode(0); # go to sleep;
    }
    elsif ( $humidity > 90 ) {
        # email warning that there are dangerous conditions for the sensor
        LOG("WARNING!! Humidity is too high even for storage!");
        save_data($dt, $temp, $humidity, '', '');
    }
    else {
        LOG("Current humidity is too high (>70%)for the sensor to provide acurate reading.");
        save_data($dt, $temp, $humidity, '', '');
    }

    LOG('-' x 10);
    sleep 60 * 15; # 60 seconds x XX minutes
}