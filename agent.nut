local postUrlThingspeak = "https://api.thingspeak.com/update";
local getUrlThingspeak = "https://api.thingspeak.com/channels/419908/fields/"
local postUrlAdafruit = "https://io.adafruit.com/api/v2/chriscrewdson/groups/work-monitor/data";

local postHeadersThingspeak = {
  "Content-Type": "application/x-www-form-urlencoded",
  "X-THINGSPEAKAPIKEY": "B8NHXCQDZF53T3LM"
};
local postHeadersAdafruit = {
    "X-AIO-Key": "b750eb66735345aea7146aca1f5341bd",
    "Content-Type": "application/json"
}
local getHeadersThingspeak = {
  "X-THINGSPEAKAPIKEY": "EN4U1DKNVXKIJAXI"
};

function httpPostToThingSpeak (data) {
  local request = http.post(
      postUrlThingspeak,
      postHeadersThingspeak,
      data
    );
  local response = request.sendsync();
  return response;
}

function httpPostToAdafruit (data) {
  local request = http.post(
      postUrlAdafruit,
      postHeadersAdafruit,
      data
    );
  local response = request.sendsync();
  return response;
}

function httpGetFromThingSpeak (field) {
  local request = http.get(
    getUrlThingspeak + field + ".json?results=1",
    getHeadersThingspeak
  );
  local response = request.sendsync();
  return response;
}

device.on("update", function(state) {
  server.log(format("updating working button to: %i", state.workingToggle));
  server.log(format("updating standing switch to: %i", state.standingState));
  server.log(format("Humidity: %0.1f %%", state.humidity));
  server.log(format("Temperature: %0.1f C", state.temperature));
  local thingSpeakResponse = httpPostToThingSpeak(
    "field1=1" +
    "&field2=" + state.workingToggle +
    "&field3=" + state.standingState +
    "&field4=" + state.humidity +
    "&field5=" + state.temperature
  );
//   server.log("thingspeak response body: " + thingSpeakResponse.body);
  server.log("thingspeak response code: " + thingSpeakResponse.statuscode);

  local adafruitRequest = format(
    "{\"feeds\":[{\"key\":\"working\",\"value\":\"%i\"},{\"key\":\"standing\",\"value\":\"%i\"},{\"key\":\"temperature\",\"value\":\"%f\"},{\"key\":\"humidity\",\"value\":\"%f\"}]}",
    state.workingToggle,
    state.standingState,
    state.temperature,
    state.humidity
  );
//   server.log("adafruit request: " + adafruitRequest);
  local adafruitResponse = httpPostToAdafruit(adafruitRequest);
//   server.log("adafruit response body: " + adafruitResponse.body);
  server.log("adafruit response code: " + adafruitResponse.statuscode);
});

device.on("get", function(field) {
  local response = httpGetFromThingSpeak(field);
  //server.log("field " + field + " get response: " + response.body);
  local responseDecoded = http.jsondecode(response.body);
  local fieldValue = responseDecoded.feeds[0]["field"+field];
  //server.log("decoded feed field: " + fieldValue);
  device.send("setLed", fieldValue);
});
