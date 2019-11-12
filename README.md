# Air Quality Monitor

Air Monitor based on Raspberry Pi, SDS011 laser dust sensor, and DHT22 temperature and humidity sensor.

* Communications with SDS011 sensor are using the included `Device::SDS011` Perl module
* Communications with DHT22 sensor are using [pigpiod library](http://abyz.me.uk/rpi/pigpio/) and `RPi::PIGPIO::Device::DHT22` available on CPAN

## Hardware Setup

Devices Used

* Raspberry Pi Zero W (configured for headless use)
* SDS011 particulate matter sensor by Nova Fitness
* DHT22 temperature and humidity sensor

Raspberry Pi configured for headless use (there are multitude of tutorials online on how to set it up).
SDS011 came with a USB adapter, so it is connected to RPi's micro USB port via USB-to-Micro USB adapter cable.
DHT22 was soldered directly to RPi, as there are no header pins on RPi Zero W.

## Software Setup

*SDS011 dust sensor*

`Device::SerialPort` module is used to communicate with the PM sensor. The device utilizes a [simple communication protocol](http://...), which is implemented in `Device::SDS011` module (version 1.3 of the protocol is implemented).

In the default mode (which resets upon reboot), the sensor works in continuous mode, emitting PM readings every second. Service life of the laser diode inside the seosor device has service life up to 8000 hours. So, unless it is used for real-time monitoring, it would be wise to use lower frequesny of reading by keeping the device in sleep mode between data readings.

The included sample program uses following algorithm while working with sensor:

- wake up: bring sensor out of the sensor mode
- wait 10 seconds to warm up
- read values (get average of 3 readings)
- put sensor to sleep mode
- sleep 30 minutes
- repeat

*DHT22 temperature and humidity sensor*

[PIGPIO software library](http://...) along with the `RPi::PIGPIO` and the `RPi::PIGPIO::Device::DHT22` modules (both available on CPAN), is used to get temerature and humidity readings. The PIGPIO software runs in the background as a local web server, and provides communication with RPi data pins. The mentioned modules communicate to RPi via this software to get data readings.


## The Problem

Turned out the SDS011 laser dust sensor gives accurate readings only when humidity is under 70%, and both of the cities I wanted to use it in have humidity over 70% most of the time. So, I'm only including the sample monitoring script, and will continue building more complete solution when another type - less sensitive to humidity levels - of sensor arrives.