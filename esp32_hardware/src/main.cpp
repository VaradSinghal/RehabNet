#include <Wire.h>
#include <WiFi.h>
#include <HTTPClient.h>

const char* ssid = "Allah-huakbar";          // Replace with your WiFi name
const char* password = "varad1526";  // Replace with your WiFi password

// Replace with the IP address of the computer running your Python Flask backend
// Ensure the ESP32 and the computer are on the exact same WiFi network!
const char* serverUrl = "http://10.177.173.46:5000/sensor-data/";

const int samplingDelayMs = 20; 

// -----------------------------------------------------------------------------
// SENSOR VARIABLES
// -----------------------------------------------------------------------------
const int MPU = 0x68;
int16_t ax, ay, az, gx, gy, gz;

long ax_offset=0, ay_offset=0, az_offset=0;
long gx_offset=0, gy_offset=0, gz_offset=0;

// -----------------------------------------------------------------------------
// SETUP
// -----------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22);

  // 1. Connect to WiFi
  Serial.print("Connecting to WiFi: ");
  Serial.println(ssid);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected! IP address:");
  Serial.println(WiFi.localIP());

  // 2. Wake MPU6050
  Wire.beginTransmission(MPU);
  Wire.write(0x6B);
  Wire.write(0);
  Wire.endTransmission(true);

  Serial.println("Calibrating sensor... Keep it still");

  for(int i = 0; i < 1000; i++){
    readMPU();

    ax_offset += ax;
    ay_offset += ay;
    az_offset += az - 16384; // Gravity is 1g on the Z axis when flat

    gx_offset += gx;
    gy_offset += gy;
    gz_offset += gz;

    delay(2);
  }

  ax_offset /= 1000;
  ay_offset /= 1000;
  az_offset /= 1000;

  gx_offset /= 1000;
  gy_offset /= 1000;
  gz_offset /= 1000;

  Serial.println("Calibration complete!");
}

// -----------------------------------------------------------------------------
// MAIN LOOP
// -----------------------------------------------------------------------------
void loop() {
  readMPU();

  // Apply calibration offsets
  float ax_cal = ax - ax_offset;
  float ay_cal = ay - ay_offset;
  float az_cal = az - az_offset;

  // Convert to g
  float ax_g = ax_cal / 16384.0;
  float ay_g = ay_cal / 16384.0;
  float az_g = az_cal / 16384.0;

  // Print to Serial map (optional, can be commented out for speed)
  Serial.print("Accel(g): ");
  Serial.print(ax_g); Serial.print(", ");
  Serial.print(ay_g); Serial.print(", ");
  Serial.println(az_g);

  // Send data to Flask backend
  sendDataToBackend(ax_g, ay_g, az_g);

  // Wait before next sample (~50Hz)
  delay(samplingDelayMs);
}

// -----------------------------------------------------------------------------
// HELPER FUNCTIONS
// -----------------------------------------------------------------------------
void readMPU() {
  Wire.beginTransmission(MPU);
  Wire.write(0x3B);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU, 14, true);

  ax = Wire.read()<<8 | Wire.read();
  ay = Wire.read()<<8 | Wire.read();
  az = Wire.read()<<8 | Wire.read();

  Wire.read(); Wire.read(); // skip temperature

  gx = Wire.read()<<8 | Wire.read();
  gy = Wire.read()<<8 | Wire.read();
  gz = Wire.read()<<8 | Wire.read();
}

void sendDataToBackend(float x, float y, float z) {
  // Check if still connected
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(serverUrl);
    http.addHeader("Content-Type", "application/json");

    // Construct the JSON payload required by the FastAPI backend
    // Format: {"user_id": 1, "ax": 0.05, "ay": 0.01, "az": 0.98, "timestamp": 1234}
    String jsonPayload = "{\"user_id\": 1" +
                         ", \"timestamp\": " + String(millis()) +
                         ", \"ax\": " + String(x, 4) + 
                         ", \"ay\": " + String(y, 4) + 
                         ", \"az\": " + String(z, 4) + "}";

    // Send POST request
    int httpResponseCode = http.POST(jsonPayload);

    if (httpResponseCode > 0) {
      // Success (HTTP 200)
      Serial.print("HTTP Code: ");
      Serial.println(httpResponseCode);
    } else {
      Serial.print("Error communicating with backend: ");
      Serial.println(httpResponseCode);
    }

    http.end();
  } else {
    Serial.println("WiFi not connected. Attempting to reconnect...");
    WiFi.disconnect();
    WiFi.reconnect();
  }
}
