#!/usr/bin/python3

### From: https://github.com/ericstaal/domoticz/blob/master/scripts/doorbell.py

# doorbell based on interrupt with filtering and logging

# settings
GPIO_doorbell = 17                                      # BCM Pin number
domoticzidx = 153                               # ID of doorbell
domoticzserver="127.0.0.1:8080"         # IP / port domoticz
domoticzusername = "pi"                         # username
domoticzpassword = "pi"                         # password

#mintimebetweenrings = 1             # in seconds (means bell is 2\X seconds blind after a press)
#logrings = True                     # logging to stdout
#minbuttonpressed = 5               # 0 = do no check, other time in milliseconds
#maxbuttonpressed = 5000             # time (ms)to wait until button press is over (only used if minbuttonpressed > 0)
mintimebetweenrings = 1             # in seconds (means bell is 2\X seconds blind after a press)
logrings = True                     # logging to stdout
minbuttonpressed = 10               # 0 = do no check, other time in milliseconds
maxbuttonpressed = 50000             # time (ms)to wait until button press is over (only used if minbuttonpressed > 0)

import RPi.GPIO as GPIO
import time
import urllib.request
import json
import traceback
import sys
import os
from subprocess import Popen, PIPE, STDOUT
#from base64 import b64encode

# Setup IO
GPIO.setwarnings(False)
GPIO.setmode(GPIO.BCM) # BOARD does not work for pin 29
GPIO.setup(GPIO_doorbell, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)

"""
https://www.domoticz.com/forum/viewtopic.php?f=65&t=18447&p=142131&hilit=doorbell#p142131
##
I've been working on a doorbell script, this should trigger when the specific GPIO pin goes low.
GPIO.setup(18, GPIO.IN, pull_up_down=GPIO.PUD_UP)

### Originele script
GPIO.setup(18, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    GPIO.wait_for_edge(GPIO_doorbell, GPIO.FALLING)
    timePressed = microTime()

    # doorbell is pressed
    if (minbuttonpressed > 0):
    result = GPIO.wait_for_edge(GPIO_doorbell, GPIO.RISING, timeout=maxbuttonpressed)

#####
https://raspi.tv/2013/rpi-gpio-basics-4-setting-up-rpi-gpio-numbering-systems-and-inputs
##
GPIO.setup(25, GPIO.IN)    # set GPIO 25 as input

    while True:            # this will carry on until you hit CTRL+C
        if GPIO.input(25): # if port 25 == 1
            print "Port 25 is 1/GPIO.HIGH/True - button pressed"
        else:
            print "Port 25 is 0/GPIO.LOW/False - button not pressed"
        sleep(0.1)         # wait 0.1 seconds

except KeyboardInterrupt:
    GPIO.cleanup()         # clean up after yourself
#####
https://www.raspberrypi.org/forums/viewtopic.php?p=614720

An input gpio will float between 0 and 1 if it's not connected to a voltage.
The pull-up/downs supply that voltage so that the gpio will have a defined value UNTIL overridden by a stronger force.
You should set a pull-down (to 0) when you expect the stronger force to pull it up to 1.
You should set a pull-up (to 1) when you expect the stronger force to pull it down to 0.
Otherwise the gpio will not change state and you'll never know about the external event.

https://sourceforge.net/p/raspberry-gpio-python/wiki/Inputs/

wait_for_edge() function
The wait_for_edge() function is designed to block execution of your program until an edge is detected. In other words, the example above that waits for a button press could be rewritten as:

GPIO.wait_for_edge(channel, GPIO.RISING)
Note that you can detect edges of type GPIO.RISING, GPIO.FALLING or GPIO.BOTH. The advantage of doing it this way is that it uses a negligible amount of CPU, so there is plenty left for other tasks.
"""
#inlog ='%s:%s' % (domoticzusername, domoticzpassword)
#base64string = b64encode(inlog.encode('utf-8')).decode('utf-8')
#Setup logging
logfile = "/var/tmp/bel.txt"
class Tee(object):
    def __init__(self, *files):
        self.files = files
    def write(self, obj):
        for f in self.files:
            f.write(obj)
    def flush(self):
        pass

f = open(logfile, 'w')
backup = sys.stdout
sys.stdout = Tee(sys.stdout, f)

def writePidFile():
  pid = str(os.getpid())
  currentFile = open('/var/tmp/run/doorbell.pid', 'w')
  currentFile.write(pid)
  currentFile.close()

def microTime():
  return int(round(time.time() * 1000))

def domoticzrequest (url):
  request = urllib.request.Request(url)
  #request.add_header("Authorization", "Basic %s" % base64string)
  response = urllib.request.urlopen(request)
  return response.read().decode('utf-8')

def microtimeToString(microtime):
  return time.strftime("%d-%m-%Y %H:%M:%S", time.localtime(microtime/1000))

def reportBell():
  domoticzrequest("http://" + domoticzserver + "/json.htm?type=command&param=switchlight&idx=" + str(domoticzidx) + "&switchcmd=On")
  time.sleep(mintimebetweenrings)
  domoticzrequest("http://" + domoticzserver + "/json.htm?type=command&param=switchlight&idx=" + str(domoticzidx) + "&switchcmd=Off")

while True:
  writePidFile()
  # Doorbell is active low, so a falling edge means the door has been pressed
  print ("Doorbell script started.")

  try:
    sys.stdout.flush()
    #GPIO.wait_for_edge(GPIO_doorbell, GPIO.FALLING)
    GPIO.wait_for_edge(GPIO_doorbell, GPIO.RISING)
    #Anders
    #GPIO.wait_for_edge(GPIO_doorbell, GPIO.BOTH)
    timePressed = microTime()

    # doorbell is pressed
    if (minbuttonpressed > 0):
      result = GPIO.wait_for_edge(GPIO_doorbell, GPIO.FALLING, timeout=maxbuttonpressed)
      if result is None:
        if logrings:
          print ("Doorbell pressed at "+ microtimeToString(timePressed)+" but not released after "+str(maxbuttonpressed)+" milliseconds, ignored.")
      else:
        timeLoose = microTime()
        pressedtime = timeLoose - timePressed

        if (pressedtime > minbuttonpressed):
          if logrings:
            print ("Doorbell pressed at "+ microtimeToString(timePressed)+" for "+str(pressedtime)+ " milliseconds, notified Domoticz.")
          reportBell()

        else:
          if logrings:
            print ("Doorbell pressed at "+ microtimeToString(timePressed)+" for "+str(pressedtime)+ " milliseconds, minimal of "+ str(minbuttonpressed) +" is required, ignored.")
    else:
      if logrings:
        print ("Doorbell pressed at "+ microtimeToString(timePressed)+", notified Domoticz")
      reportBell()
  except Exception as e:
    print ("Error occured: "+ traceback.format_exc())
