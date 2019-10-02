# Air Quality Monitor

Air Monitor (PM) based on Raspberry Pi, SDS011 laser dust sensor, and DHT22 temperature and humidity sensor.

* Communications with SDS011 sensor are using the included `Device::SDS011` Perl module
* Communications with DHT22 sensor are using [pigpiod library](http://abyz.me.uk/rpi/pigpio/) and `RPi::PIGPIO::Device::DHT22` available on CPAN

## Hardware Setup

Devices Used

* Raspberry Pi Zero W (configured for headless use)
* SDS011 particulate matter sensor by Nova Fitness
* DHT22 temperature and humidity sensor

Raspberry Pi was configured for headless use (there are multitude tutorials online how to do it).
SDS011 came with a USB adapter, so it connected directly to RPi's micro USB port (via USB-to-Micro USB adapter cable).
DHT22 was soldered directly to RPi, as thereare no header pins on RPi Zero W.

## Software Setup

## The Problem

Turned out the SDS011 laser dust sensor gives accurate readings only when humidity is under 70%, and both of the cities I wanted to use it have humidity over 70% most of the time. So, I'm only including the sample monitoring script, and will continue building more complete solution when a new type of sensor arrives.