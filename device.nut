// Copyright (c) 2014 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT
// Class for DHT11/RHT03 Temp/Humidity Sensor

const SPICLK = 937.5;
const INTERVAL = 5; // time between readings in seconds

// Class to read the DHT11/DHT22 family of temperature/humidity sensors
// See http://akizukidenshi.com/download/ds/aosong/DHT11.pdf
// These sensors us a proprietary one-wire protocol. The imp
// emulates this protocol with SPI.
// To use:
//  - tie MOSI to MISO with a 10k resistor
//  - tie MISO to the data line on the sensor
class DHT11 {
    static STARTTIME_LOW     = 0.020000; // 20 ms low time for start
    static STARTTIME_HIGH    = 0.000020; // 20 us min high time for start
    static STARTTIME_SENSOR  = 0.000080; // 80 us low / 80 us high "ACK" from sensor on START
    static MARKTIME          = 0.000050; // 50 us low pulse between 0 or 1 marks
    static ZERO              = 0.000026; // 26 us high for "0"
    static ONE               = 0.000075; // 70 us high for "1"

    _spi                 = null;
    _clkspeed            = null;
    _bittime             = null;
    _bytetime            = null;
    _start_low_bits      = null;
    _start_low_bytes     = null;
    _start_high_bits     = null;
    _start_high_bytes    = null;
    _start_ack_bits      = null;
    _start_ack_bytes     = null;
    _mark_bits           = null;
    _mark_bytes          = null;
    _zero_bits           = null;
    _zero_bytes          = null;
    _one_bits            = null;
    _one_bytes           = null;

    // class constructor
    // Input:
    //      _spi: a pre-configured SPI peripheral (e.g. spi257)
    //      _clkspeed: the speed the SPI has been configured to run at
    // Return: (None)
    constructor(spi, clkspeed) {
        _spi = spi;
        _clkspeed = clkspeed;

        _bittime     = 1.0 / (_clkspeed * 1000);
        _bytetime    = 8.0 * _bittime;

        _start_low_bits      = STARTTIME_LOW / _bittime;
        _start_low_bytes     = (_start_low_bits / 8);
        _start_high_bits     = STARTTIME_HIGH / _bittime;
        _start_high_bytes    = (_start_high_bits / 8);
        _start_ack_bits      = STARTTIME_SENSOR / _bittime;
        _start_ack_bytes     = (_start_ack_bits / 8);
        _mark_bits           = MARKTIME / _bittime;
        _mark_bytes          = (_mark_bits / 8);
        _zero_bits           = ZERO / _bittime;
        _zero_bytes          = (_zero_bits / 8);
        _one_bits            = ONE / _bittime;
        _one_bytes           = (_one_bits / 8);

        // // Pull the signal line up
        _spi.writeread("\xff");
        imp.sleep(STARTTIME_LOW);
    }

    // helper function
    // given a long blob, find times between transitions and parse to
    // temp and humidity values. Assumes 40-bit return value (16 humidity / 16 temp / 8 checksum)
    // Input:
    //      hexblob (blob of arbitrary length)
    // Return:
    //      table containing:
    //          "rh": relative humidity (float)
    //          "temp": temperature in celsius (float)
    //      if read fails, rh and temp will return 0
    function parse(hexblob) {
        local laststate     = 0;
        local lastbitidx    = 0;

        local gotack        = false;
        local rawidx        = 0;
        local result        = blob(5); // 2-byte humidity, 2-byte temp, 1-byte checksum

        local humid         = 0.0;
        local temp          = 0.0;

        // iterate through each bit of each byte of the returned signal
        for (local byte = 0; byte < hexblob.len(); byte++) {
            for (local bit = 7; bit >= 0; bit--) {

                local thisbit = (hexblob[byte] & (0x01 << bit)) ? 1:0;

                if (thisbit != laststate) {
                    if (thisbit) {
                        // low-to-high transition; watch to see how long it is high
                        laststate = 1;
                        lastbitidx = (8 * byte) + (7 - bit);
                    } else {
                        // high-to-low transition;
                        laststate = 0;
                        local idx = (8 * byte) + (7 - bit);
                        local hightime = (idx - lastbitidx) * _bittime;

                        // we now have one valid bit of info. Figure out what symbol it is.
                        local resultbyte = (rawidx / 8);
                        local resultbit =  7 - (rawidx % 8);
                        //server.log(format("bit %d of byte %d",resultbit, resultbyte));
                        if (hightime < ZERO) {
                            // this is a zero
                            if (gotack) {
                                // don't record any data before the ACK is seen
                                result[resultbyte] = result[resultbyte] & ~(0x01 << resultbit);
                                rawidx++;
                            }
                        } else if (hightime < ONE) {
                            // this is a one
                            if (gotack) {
                                result[resultbyte] = result[resultbyte] | (0x01 << resultbit);
                                rawidx++;
                            }
                        } else {
                            // this is a START ACK
                            gotack = true;
                        }
                    }
                }
            }
        }

        server.log(format("parsed: 0x %02x%02x %02x%02x %02x",result[0],result[1],result[2],result[3],result[4]));
        humid = (result[0] * 1.0) + (result[1] / 1000.0);
        if (result[2] & 0x80) {
            // negative temperature
            result[2] = ((~result[2]) + 1) & 0xff;
        }
        temp = (result[2] * 1.0) + (result[3] / 1000.0);
        if (((result[0] + result[1] + result[2] + result[3]) & 0xff) != result[4]) {
            return {"rh":0.0,"temp":0.0};
        } else {
            server.log(format("Relative Humidity: %0.1f %%", humid));
            server.log(format("Temperature: %0.1f C", temp));
            return {"rh":humid,"temp":temp};
        }
    }

    // read the sensor
    // Input: (none)
    // Return:
    //      table containing:
    //          "rh": relative humidity (float)
    //          "temp": temperature in celsius (float)
    //      if read fails, rh and temp will return 0
    function read() {
        local bloblen = _start_low_bytes + _start_high_bytes + (40 * (_mark_bytes + _one_bytes));
        local startblob = blob(bloblen);
        for (local i = 0; i < _start_low_bytes; i++) {
            startblob.writen(0x00,'b');
        }
        for (local j = _start_low_bytes; j < bloblen; j++) {
            startblob.writen(0xff,'b');
        }

        //server.log(format("Sending %d bytes", startblob.len()));
        local result = _spi.writeread(startblob);
        return parse(result);
    }
}

function MCP9808() {
  local addr=0x18; // default
  local laddr=addr<<1;
  local cmd=0x05
  local val=i2c.read(laddr,cmd.tochar(),2);
  local error=i2c.readerror();

  if (error != 0) {
    server.log("MCP9808 Error= "+error)
  }
  local result = val[0] << 8;
  result = result + val[1];
  local temp = (result & 0x0FFF) / 16.0;
  if (result & 0x1000) temp -= 256;
  return temp;
}


local ignoreButton = false;
local ignoreSwitch = false;
local state = {
    workingToggle = 1,
    standingState = 1,
    humidity = 0.0,
    temperature = 0.0
};
local synced = false;

led <- hardware.pin8;
button <- hardware.pin1;
switchPin <- hardware.pin9;

function debounceButton() {
  server.log("debounced");
  ignoreButton = false;
}

function buttonPress() {
  if (!ignoreButton){
    local buttonState = button.read();

    if (buttonState == 1) {
      server.log("button pressed: " + buttonState);
    } else {
      server.log("button released: " + buttonState);
    }

    if (buttonState == 1) {
      switchPress(); //also read the standing switch
      state.workingToggle = 1 - state.workingToggle;
      server.log("setting working status to: " + state.workingToggle)
      led.write(state.workingToggle);
      agent.send("update", state);
    }

    ignoreButton = true;
    imp.wakeup(0.5, debounceButton);
  }
}

function debounceSwitch() {
  ignoreSwitch = false;
}

function switchPress() {
  if (!ignoreSwitch){
    local switchState = switchPin.read();

    // if (switchState == 1) {
    //   server.log("switch pressed: " + switchState);
    // } else {
    //   server.log("switch released: " + switchState);
    // }

    state.standingState = switchState;

    // agent.send("update", state);

    ignoreSwitch = true;
    imp.wakeup(0.5, debounceSwitch);
  }
}

function setLed(value) {
  synced = true;
  server.log("setLed value from agent: " + value);
  state.workingToggle = value.tointeger();
  // server.log("workingToggle: " + workingToggle);
  led.write(state.workingToggle == 1 ? 1.0 : 0.0);
};

function pollForLife(){
  server.log("polling");
  switchPress(); // also read the standing switch
  // check temperature
  local dht11Data = dht11.read();
//   server.log(format("Relative Humidity: %0.1f",dht11Data.rh)+" %");
//   server.log(format("Temperature: %0.1f C",dht11Data.temp));
  state.humidity = dht11Data.rh;
  state.temperature = dht11Data.temp;
  agent.send("update", state);
//   agent.send("get", "2");
  imp.wakeup(300, pollForLife);
}

button.configure(DIGITAL_IN_PULLUP, buttonPress);
switchPin.configure(DIGITAL_IN_PULLUP, switchPress);
led.configure(PWM_OUT, 1.0 / 400.0, 0.0);

ledState <- 0.0;
ledChange <- 0.05;

spi         <- hardware.spi257;
clkspeed    <- spi.configure(MSB_FIRST, SPICLK);

dht11 <- DHT11(spi, clkspeed);

// i2c<-hardware.i2c12; //i2c12 or i2c89
// i2c.configure(CLOCK_SPEED_400_KHZ);


function pulse() {
  led.write(ledState);
  ledState = ledState + ledChange;

  if (ledState >= 1.0 || ledState <= 0.0) ledChange = ledChange * -1.0;

  if (!synced) {
    imp.wakeup(0.05, pulse);
  }
}
pulse();

//led.write(1); //Startup with light on
// check for current status and update LED on response
agent.on("setLed", setLed)
agent.send("get", "2");
pollForLife();
