# homebridge2openluup
Sharing what I believe is a great way to add support to devices that used to work but since existing plugin haven't been maintain by the original authors (or any other developer in the community) have stopped working as they've abandon or moved to other platform...

Homebridge has a large and very active community and I think this type of plugin will a good way to benefit from it, It will bring any device that have been configured in homebridge into openluup.

Currently it support, thermostat (Nest and others), Switches (Specially MyQ), Dimmers, Switches, Motion Sensors, Door Lock (Open/close) Support to other type of device can easily be added.


Installation:

upload the files to /you_openluup_directory/files/
create a new device with D_Homebridge2openluup1.xml

Set your hombredige IP, username, password to the deivce's attributes

Capture the uuid of the device you would like to bring from Homebridge into openluup by looking at your openluup logs when starting

based on the device type, set DeviceList Variable

T for thermostat
D for dimmers
S for switches
G for garage doors
L for Locks
A for motion sensors

and build a string device type are delimited by a ; (semicolong) and device's uui by a , (comma) like this:
T:homebridge_thermostat1_uuid,homebridge_thermostat2_uuid;D:homebridge_dimmer1_uuid,homebridge_dimmer2_uuid etc

This still in beta, would love to add async next and support to shades and other sensors.

Visit https://smarthome.community/topic/436/homebridge-to-openluup/ for more info