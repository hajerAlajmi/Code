#include <WiFi.h> // Enables ESP32 Wi-Fi connection features
#include <HTTPClient.h> // Lets the ESP32 send HTTP requests to Firebase
 
// WIFI
// These credentials are used so the ESP32 can connect to the local network
// before sending any sensor data online.
const char* ssid = "HUAWEI_H112_9DD7";
const char* password = "JY7H0NA5DMQ";
 
// FIREBASE
// firebaseHost is the Realtime Database base URL.
// firebaseAuth is left empty here, which means no database secret/token is being added.
const char* firebaseHost = "https://safe-home-monitor-default-rtdb.firebaseio.com";
String firebaseAuth = "";
 
// PINS
// Each sensor is connected to a specific ESP32 pin.
// These pin definitions make the code easier to read and update later.
#define PIR_PIN         13
#define VIBRATION_PIN   12
#define DOOR_PIN        14
#define TEMP_PIN        32
#define PRESSURE1_PIN   34
#define PRESSURE2_PIN   35
 
// SETTINGS
// lastSendTime helps control how often data is sent.
// sendInterval = 2000 means sensor data is uploaded every 2 seconds.
// pressureThreshold is the analog cutoff used to decide if pressure is being applied.
unsigned long lastSendTime = 0;
const unsigned long sendInterval = 2000;
const int pressureThreshold = 500;
 
// WIFI CONNECT
// This function keeps trying until Wi-Fi is connected.
// It also prints useful connection details to the Serial Monitor for debugging.
void connectWiFi() {
  WiFi.begin(ssid, password);
 
  Serial.println("====================================");
  Serial.println("Connecting to WiFi...");
 
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
 
  Serial.println();
  Serial.println("WiFi connected");
  Serial.print("IP: ");
  Serial.println(WiFi.localIP());
  Serial.println("====================================");
}
 
// READ TEMPERATURE
// for analog temp sensor like LM35
// This converts the analog reading into voltage first,
// then converts that voltage into Celsius based on LM35 behavior
// (10 mV per 1 degree C, so voltage * 100).
float readTemperatureC() {
  int raw = analogRead(TEMP_PIN);
  float voltage = (raw / 4095.0) * 3.3;
  float temperatureC = voltage * 100.0;
  return temperatureC;
}
 
// SEND TO FIREBASE
// This sends JSON sensor data to a specific path in Firebase Realtime Database.
// It first checks Wi-Fi, rebuilds the full URL, then performs an HTTP PUT request.
// PUT replaces the value at that path with the new JSON object.
void sendToFirebase(String path, String jsonData) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi disconnected. Reconnecting...");
    connectWiFi();
    return; // Stops sending for now until Wi-Fi is back
  }
 
  HTTPClient http;
  String url = String(firebaseHost) + path;
 
  if (firebaseAuth.length() > 0) {
    url += "?auth=" + firebaseAuth; // Adds auth only if a token/secret exists
  }
 
  http.begin(url);
  http.addHeader("Content-Type", "application/json"); // Tells Firebase we are sending JSON
 
  int httpResponseCode = http.PUT(jsonData);
 
  Serial.println("---------- FIREBASE ----------");
  Serial.print("HTTP Response: ");
  Serial.println(httpResponseCode);
 
  if (httpResponseCode > 0) {
    String response = http.getString(); // Reads Firebase response body when request succeeds
    Serial.print("Firebase Response: ");
    Serial.println(response);
  } else {
    Serial.print("Error: ");
    Serial.println(http.errorToString(httpResponseCode)); // Prints readable error text
  }
 
  Serial.println("------------------------------");
  http.end(); // Frees HTTP resources after request is complete
}
 
// SETUP
// Runs once when the ESP32 starts.
// This initializes Serial output, sensor pin modes, ADC resolution,
// connects to Wi-Fi, and prints startup messages.
void setup() {
  Serial.begin(115200);
  delay(1000); // Small startup delay for stability and clearer Serial output
 
  pinMode(PIR_PIN, INPUT);
  pinMode(VIBRATION_PIN, INPUT);
  pinMode(DOOR_PIN, INPUT_PULLUP); // INPUT_PULLUP means the pin uses an internal pull-up resistor
 
  analogReadResolution(12); // ESP32 analog readings will be from 0 to 4095
 
  connectWiFi();
 
  Serial.println("System started");
  Serial.println("Reading sensors every 2 seconds...");
}
 
// LOOP
// Runs continuously after setup.
// The timing condition makes sure readings are only sent every sendInterval.
// Inside this block, all sensors are read, interpreted, printed, packed into JSON, and then uploaded to Firebase.
void loop() {
  if (millis() - lastSendTime >= sendInterval) {
    lastSendTime = millis(); // Updates the last upload time once this cycle starts
 
    int pirRaw = digitalRead(PIR_PIN);
    int vibrationRaw = digitalRead(VIBRATION_PIN);
    int doorRaw = digitalRead(DOOR_PIN);
 
    int tempRaw = analogRead(TEMP_PIN);
    float temperatureC = readTemperatureC();
 
    int pressure1Raw = analogRead(PRESSURE1_PIN);
    int pressure2Raw = analogRead(PRESSURE2_PIN);

  // These boolean values convert raw sensor readings into clearer logical meanings
    bool motionDetected = (pirRaw == HIGH);
    bool vibrationDetected = (vibrationRaw == HIGH);
    bool doorOpen = (doorRaw == HIGH);
    bool pressure1Pressed = (pressure1Raw > pressureThreshold);
    bool pressure2Pressed = (pressure2Raw > pressureThreshold);
 
    Serial.println();
    Serial.println("====================================");
    Serial.println("LIVE SENSOR STATUS");
    Serial.println("====================================");
 
  // Prints motion sensor reading in both raw and interpreted forms
    Serial.print("Motion Sensor     -> Raw: ");
    Serial.print(pirRaw);
    Serial.print(" | Status: ");
    Serial.println(motionDetected ? "MOTION DETECTED" : "NO MOTION");
 
  // Prints vibration sensor reading in both raw and interpreted forms
    Serial.print("Vibration Sensor  -> Raw: ");
    Serial.print(vibrationRaw);
    Serial.print(" | Status: ");
    Serial.println(vibrationDetected ? "VIBRATION DETECTED" : "NO VIBRATION");
 
  // Prints door sensor reading in both raw and interpreted forms
    Serial.print("Door Sensor       -> Raw: ");
    Serial.print(doorRaw);
    Serial.print(" | Status: ");
    Serial.println(doorOpen ? "DOOR OPEN" : "DOOR CLOSED");
 
  // Shows raw temperature ADC value and calculated Celsius value
    Serial.print("Temperature Sensor-> Raw: ");
    Serial.print(tempRaw);
    Serial.print(" | Temp C: ");
    Serial.println(temperatureC);
 
  // Prints first pressure sensor reading and threshold-based status
    Serial.print("Pressure Sensor 1 -> Raw: ");
    Serial.print(pressure1Raw);
    Serial.print(" | Status: ");
    Serial.println(pressure1Pressed ? "PRESSED" : "NOT PRESSED");
 
  // Prints second pressure sensor reading and threshold-based status
    Serial.print("Pressure Sensor 2 -> Raw: ");
    Serial.print(pressure2Raw);
    Serial.print(" | Status: ");
    Serial.println(pressure2Pressed ? "PRESSED" : "NOT PRESSED");
 
 // Extra warning in case temperature sensor seems disconnected or not reading properly
    if (tempRaw == 0) {
      Serial.println("WARNING: Temperature sensor reading is 0");
    }
 
    Serial.println("====================================");
 
 // Manual JSON construction starts here.
 // Each sensor is stored as its own object with raw reading + readable status.
    String jsonData = "{";
    jsonData += "\"motion\":{";
    jsonData += "\"raw\":" + String(pirRaw) + ",";
    jsonData += "\"status\":\"" + String(motionDetected ? "detected" : "no_motion") + "\"";
    jsonData += "},";
 
    jsonData += "\"vibration\":{";
    jsonData += "\"raw\":" + String(vibrationRaw) + ",";
    jsonData += "\"status\":\"" + String(vibrationDetected ? "detected" : "no_vibration") + "\"";
    jsonData += "},";
 
    jsonData += "\"door\":{";
    jsonData += "\"raw\":" + String(doorRaw) + ",";
    jsonData += "\"status\":\"" + String(doorOpen ? "open" : "closed") + "\"";
    jsonData += "},";
 
    jsonData += "\"temperature\":{";
    jsonData += "\"raw\":" + String(tempRaw) + ",";
    jsonData += "\"celsius\":" + String(temperatureC, 2) + ","; // Sends temperature with 2 decimal places
    jsonData += "\"status\":\"normal\""; // Currently fixed as normal; no threshold logic is applied here yet
    jsonData += "},";
 
    jsonData += "\"pressure1\":{";
    jsonData += "\"raw\":" + String(pressure1Raw) + ",";
    jsonData += "\"status\":\"" + String(pressure1Pressed ? "pressed" : "not_pressed") + "\"";
    jsonData += "},";
 
    jsonData += "\"pressure2\":{";
    jsonData += "\"raw\":" + String(pressure2Raw) + ",";
    jsonData += "\"status\":\"" + String(pressure2Pressed ? "pressed" : "not_pressed") + "\"";
    jsonData += "}";
 
    jsonData += "}";

  // Sends the completed JSON object to the /sensors node in Firebase
    sendToFirebase("/sensors.json", jsonData);
  }
}