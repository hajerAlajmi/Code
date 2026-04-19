#include "esp_camera.h"  // Core ESP32-CAM camera driver
#include <WiFi.h>  // Wi-Fi connection support
#include <HTTPClient.h> // HTTP requests for sending heartbeat to Firebase
#include <WiFiClientSecure.h> // Secure HTTPS client
#include <time.h> // Time-related utilities
 

// Select camera model
#define CAMERA_MODEL_AI_THINKER
#include "camera_pins.h" // Loads the correct GPIO pin definitions for the selected camera model
 
// Enter your WiFi credentials
// These credentials let the ESP32-CAM join the local network so it can stream video
// and send camera status updates to Firebase.
const char* ssid = "HUAWEI_H112_9DD7";
const char* password = "JY7H0NA5DMQ";
 const char* firebaseHost = "https://safe-home-monitor-default-rtdb.firebaseio.com";

// Heartbeat timing keeps the app informed that the camera is still online.
// Instead of constantly sending updates, the device reports every 5 seconds.
unsigned long lastHeartbeat = 0;
const unsigned long heartbeatInterval = 5000;

void startCameraServer();  // Starts the built-in camera web server used for live stream access
void setupLedFlash(int pin); // Prepares flash LED support when the board exposes a flash pin

 // Returns the current time in milliseconds using system time.
// This is used so Firebase stores a precise "last seen" timestamp for the camera.
long long getNowMs() {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return ((long long)tv.tv_sec * 1000LL) + (tv.tv_usec / 1000);
}

void sendCameraHeartbeat() {
  // Sends a lightweight online-status update to Firebase.
  // The app can use this to decide whether the camera is currently online or stale.
  if (WiFi.status() != WL_CONNECTED) return;

  WiFiClientSecure client;
  client.setInsecure();
   // setInsecure() disables certificate validation.
  // This makes HTTPS easier to use on ESP32, but it is less strict from a security standpoint.

  HTTPClient http;

  String url = String(firebaseHost) + "/sensors/camera.json";
  long long nowMs = getNowMs();
 
  // Build a small JSON object that only updates the lastSeen timestamp.
  String body = "{\"lastSeen\":";
  body += String((unsigned long long)nowMs);
  body += "}";

  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");

  int code = http.PATCH(body);
  // PATCH is used so only the camera node field is updated instead of replacing a larger object.

  Serial.print("Heartbeat code: ");
  Serial.println(code);

  http.end(); // Always close the HTTP session to free resources
}

void setup() {
  Serial.begin(115200);
  Serial.setDebugOutput(true); // Enables deeper camera/Wi-Fi debug logging to Serial
  Serial.println();
 
  camera_config_t config;
  // This structure defines exactly how the camera should operate:
  // pins, format, resolution, buffer behavior, and image quality.
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000; // Standard external clock speed for camera sensor
  config.frame_size = FRAMESIZE_UXGA; // Start with high resolution if hardware can support it
  config.pixel_format = PIXFORMAT_JPEG; // JPEG is best for web streaming
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.jpeg_quality = 12;
config.fb_count = 2;
config.grab_mode = CAMERA_GRAB_LATEST;  // if PSRAM IC present, init with UXGA resolution and higher JPEG quality
 
  // If PSRAM is present, the board can handle better image quality and more frame buffers.
  // Without PSRAM, the code drops to a smaller frame size to avoid memory issues.
  if (config.pixel_format == PIXFORMAT_JPEG) {
    if (psramFound()) {
      config.jpeg_quality = 10;
      config.fb_count = 2;
      config.grab_mode = CAMERA_GRAB_LATEST;
    } else {
      // Limit the frame size when PSRAM is not available
      config.frame_size = FRAMESIZE_SVGA;
      config.fb_location = CAMERA_FB_IN_DRAM;
    }
  } else {
    // Best option for face detection/recognition
    // RGB formats need different sizing because they use much more memory than JPEG.
    config.frame_size = FRAMESIZE_240X240;
  #if CONFIG_IDF_TARGET_ESP32S3
    config.fb_count = 2;
  #endif
  }
 
#if defined(CAMERA_MODEL_ESP_EYE)
  // Some board models need these internal pullups enabled for correct operation.
  pinMode(13, INPUT_PULLUP);
  pinMode(14, INPUT_PULLUP);
#endif
 
  // camera init
  // This is the most important hardware setup step.
  // If camera initialization fails here, streaming cannot start.
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x", err);
    return;
  }
 
  sensor_t * s = esp_camera_sensor_get();
    // Access the sensor settings directly so image orientation and appearance can be tuned.

  // initial sensors are flipped vertically and colors are a bit saturated
  // This block corrects known behavior for the OV3660 sensor.
  if (s->id.PID == OV3660_PID) {
    s->set_vflip(s, 1); // flip it back
    s->set_brightness(s, 1); // up the brightness just a bit
    s->set_saturation(s, -2); // lower the saturation
  }
  // drop down frame size for higher initial frame rate
 // Even if setup starts high, this lowers the stream to QVGA for smoother live viewing.
  if(config.pixel_format == PIXFORMAT_JPEG){
    s->set_framesize(s, FRAMESIZE_QVGA);
  }
 
#if defined(CAMERA_MODEL_M5STACK_WIDE) || defined(CAMERA_MODEL_M5STACK_ESP32CAM)
   // Some boards need manual flipping/mirroring so the image orientation looks correct.
  s->set_vflip(s, 1);
  s->set_hmirror(s, 1);
#endif
 
#if defined(CAMERA_MODEL_ESP32S3_EYE)
  s->set_vflip(s, 1);
#endif
 
// Setup LED FLash if LED pin is defined in camera_pins.h
#if defined(LED_GPIO_NUM)
  // Enables optional flash LED support for boards that include one.
  setupLedFlash(LED_GPIO_NUM);
#endif
 
  WiFi.begin(ssid, password);
  WiFi.setSleep(false);
    // Disabling Wi-Fi sleep can improve streaming stability and reduce lag.
 
  while (WiFi.status() != WL_CONNECTED) {
    delay(500); // Wait until the board is online before starting services
    Serial.print(".");
  }
  Serial.println("");
  Serial.println("WiFi connected");
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
   // Synchronizes device time with NTP servers so timestamps are accurate.

  startCameraServer();
   // Starts the ESP32-CAM web server that provides the live stream endpoint.

  Serial.print("Camera Ready! Use 'http://");
  Serial.print(WiFi.localIP());
  Serial.println("' to connect");
    // Prints the local stream URL so it can be opened from a browser or embedded in the app.
}
 
void loop() {
  // The main loop only handles periodic heartbeat updates.
  // Video streaming itself is handled by the camera web server started in setup().
  if (millis() - lastHeartbeat >= heartbeatInterval) {
    lastHeartbeat = millis();
    sendCameraHeartbeat();
  }

  delay(100);  // Small delay reduces unnecessary CPU spinning
}