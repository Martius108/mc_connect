/*
 * MC_Connect - Knob und Slider Widget Test
 * 
 * Dieses Skript testet die Knob- und Slider-Widgets mit einer LED an GPIO 16.
 * 
 * Hardware:
 * - Raspberry Pi Pico W (oder ESP8266/ESP32)
 * - LED mit Vorwiderstand (220Ω - 1kΩ) an GPIO 16
 * 
 * Funktionen:
 * - Empfängt MQTT-Commands von der MC_Connect App
 * - Steuert LED-Helligkeit über PWM (0-1024)
 * - Sendet Telemetry-Feedback zurück an die App
 * - Sendet Acknowledgment-Nachrichten
 * 
 * MQTT Topics:
 * - Empfängt: device/{deviceId}/command
 * - Sendet: device/{deviceId}/telemetry/{keyword}
 * - Sendet: device/{deviceId}/ack
 * - Sendet: device/{deviceId}/status
 */

// Automatische Erkennung des Boards
#ifdef ARDUINO_ARCH_RP2040
  // Raspberry Pi Pico W
  #include <WiFi.h>
  #define BOARD_TYPE "Raspberry Pi Pico W"
#elif defined(ESP8266)
  #include <ESP8266WiFi.h>
  #define BOARD_TYPE "ESP8266"
#elif defined(ESP32)
  #include <WiFi.h>
  #define BOARD_TYPE "ESP32"
#else
  #error "Dieses Skript unterstützt nur Raspberry Pi Pico W, ESP8266 oder ESP32!"
#endif

#include <PubSubClient.h>
#include <ArduinoJson.h>

// ============================================
// KONFIGURATION - BITTE ANPASSEN
// ============================================

// WiFi Einstellungen
const char* ssid = "DEIN_WIFI_SSID";
const char* password = "DEIN_WIFI_PASSWORT";

// MQTT Broker Einstellungen
const char* mqtt_broker = "192.168.1.100";  // IP-Adresse deines MQTT Brokers
const int mqtt_port = 1883;
const char* mqtt_username = "";  // Optional: MQTT Benutzername
const char* mqtt_password = "";  // Optional: MQTT Passwort

// Device ID - muss mit der Device ID in der App übereinstimmen
const char* device_id = "pico_test";

// LED Konfiguration
const int LED_PIN = 16;           // GPIO PIN für die LED (GPIO 16 auf Pico W)
const char* led_keyword = "led";  // Telemetry Keyword - muss mit dem Widget in der App übereinstimmen

// ============================================
// GLOBALE VARIABLEN
// ============================================

WiFiClient espClient;
PubSubClient mqtt_client(espClient);

int current_pwm_value = 0;  // Aktueller PWM-Wert (0-1024)

// MQTT Topics
String command_topic;
String telemetry_topic;
String ack_topic;
String status_topic;

// ============================================
// SETUP
// ============================================

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n\n=========================================");
  Serial.println("MC_Connect - Knob/Slider Test");
  Serial.print("Board: ");
  Serial.println(BOARD_TYPE);
  Serial.println("=========================================\n");
  
  // MQTT Topics initialisieren
  command_topic = "device/" + String(device_id) + "/command";
  telemetry_topic = "device/" + String(device_id) + "/telemetry/" + String(led_keyword);
  ack_topic = "device/" + String(device_id) + "/ack";
  status_topic = "device/" + String(device_id) + "/status";
  
  // GPIO initialisieren
  pinMode(LED_PIN, OUTPUT);
  analogWrite(LED_PIN, 0);  // LED initial aus
  current_pwm_value = 0;
  
  Serial.println("LED initialisiert an PIN " + String(LED_PIN));
  
  // WiFi verbinden
  setup_wifi();
  
  // MQTT verbinden
  mqtt_client.setServer(mqtt_broker, mqtt_port);
  mqtt_client.setCallback(mqtt_callback);
  connect_mqtt();
  
  // Initialen Status senden
  send_status("online");
  send_telemetry(current_pwm_value);
  
  Serial.println("\nSetup abgeschlossen!");
  Serial.println("Bereit für Commands...\n");
}

// ============================================
// HAUPTSCHLEIFE
// ============================================

void loop() {
  // MQTT-Verbindung prüfen und aufrechterhalten
  if (!mqtt_client.connected()) {
    connect_mqtt();
  }
  mqtt_client.loop();
  
  delay(10);  // Kurze Pause für Stabilität
}

// ============================================
// WIFI SETUP
// ============================================

void setup_wifi() {
  Serial.print("Verbinde mit WiFi: ");
  Serial.println(ssid);
  
  #ifdef ARDUINO_ARCH_RP2040
    // Raspberry Pi Pico W - WiFi.begin() benötigt SSID und Passwort direkt
    WiFi.begin(ssid, password);
  #else
    // ESP8266/ESP32
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid, password);
  #endif
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi verbunden!");
    Serial.print("IP-Adresse: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\nWiFi-Verbindung fehlgeschlagen!");
    Serial.println("Bitte SSID und Passwort überprüfen.");
    Serial.print("WiFi Status: ");
    Serial.println(WiFi.status());
  }
}

// ============================================
// MQTT VERBINDUNG
// ============================================

void connect_mqtt() {
  while (!mqtt_client.connected()) {
    Serial.print("Verbinde mit MQTT Broker...");
    
    String client_id = "MC_Connect_" + String(device_id) + "_" + String(random(0xffff), HEX);
    
    if (mqtt_client.connect(client_id.c_str(), mqtt_username, mqtt_password)) {
      Serial.println(" verbunden!");
      
      // Command Topic abonnieren
      mqtt_client.subscribe(command_topic.c_str());
      Serial.println("Abonniert: " + command_topic);
      
      // Status senden
      send_status("online");
      
    } else {
      Serial.print(" fehlgeschlagen, rc=");
      Serial.print(mqtt_client.state());
      Serial.println(" - Versuche es in 5 Sekunden erneut...");
      delay(5000);
    }
  }
}

// ============================================
// MQTT CALLBACK - Verarbeitet eingehende Commands
// ============================================

void mqtt_callback(char* topic, byte* payload, unsigned int length) {
  // Payload in String umwandeln
  String message = "";
  for (int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  
  Serial.println("\n📥 Command empfangen:");
  Serial.println("Topic: " + String(topic));
  Serial.println("Payload: " + message);
  
  // JSON parsen
  StaticJsonDocument<256> doc;
  DeserializationError error = deserializeJson(doc, message);
  
  if (error) {
    Serial.println("❌ JSON Parse Fehler: " + String(error.c_str()));
    send_ack_error("JSON Parse Fehler: " + String(error.c_str()));
    return;
  }
  
  // Command-Typ prüfen
  String cmd_type = doc["type"] | "";
  
  if (cmd_type == "gpio") {
    handle_gpio_command(doc);
  } else {
    Serial.println("⚠️ Unbekannter Command-Typ: " + cmd_type);
    send_ack_error("Unbekannter Command-Typ: " + cmd_type);
  }
}

// ============================================
// GPIO COMMAND HANDLER
// ============================================

void handle_gpio_command(JsonDocument& doc) {
  int pin = doc["pin"] | -1;
  int value = doc["value"] | -1;
  String mode = doc["mode"] | "output";
  
  Serial.println("\n🔧 GPIO Command:");
  Serial.println("  PIN: " + String(pin));
  Serial.println("  Wert: " + String(value));
  Serial.println("  Modus: " + mode);
  
  // Prüfe ob es unser LED-PIN ist
  if (pin != LED_PIN) {
    Serial.println("⚠️ Ignoriere Command für PIN " + String(pin) + " (nicht konfiguriert)");
    send_ack_error("PIN " + String(pin) + " nicht konfiguriert");
    return;
  }
  
  // Prüfe Wertbereich (0-1024 für PWM)
  if (value < 0 || value > 1024) {
    Serial.println("❌ Ungültiger Wert: " + String(value) + " (muss 0-1024 sein)");
    send_ack_error("Ungültiger Wert: " + String(value) + " (muss 0-1024 sein)");
    return;
  }
  
  // Setze PWM-Wert
  // Pico W: analogWrite unterstützt 0-255 (8-bit PWM)
  // ESP8266: analogWrite unterstützt 0-1023
  // ESP32: analogWrite unterstützt standardmäßig 0-255
  #ifdef ARDUINO_ARCH_RP2040
    // Raspberry Pi Pico W: Skaliere 0-1024 auf 0-255
    int pwm_value = map(value, 0, 1024, 0, 255);  // Pico W: 0-1024 -> 0-255
  #elif defined(ESP8266)
    int pwm_value = (value > 1023) ? 1023 : value;  // ESP8266: 0-1023
  #elif defined(ESP32)
    // ESP32: Skaliere 0-1024 auf 0-255 für analogWrite
    int pwm_value = map(value, 0, 1024, 0, 255);  // ESP32: 0-1024 -> 0-255
  #else
    int pwm_value = value;
  #endif
  
  analogWrite(LED_PIN, pwm_value);
  current_pwm_value = value;  // Speichere den ursprünglichen Wert für Telemetry
  
  Serial.println("✅ LED auf PIN " + String(LED_PIN) + " gesetzt: PWM = " + String(value));
  
  // Sende sofort Telemetry-Feedback (wichtig für Widgets!)
  send_telemetry(value);
  
  // Sende Acknowledgment
  send_ack_success(pin, value);
}

// ============================================
// TELEMETRY SENDEN
// ============================================

void send_telemetry(int value) {
  // Erstelle JSON Payload
  StaticJsonDocument<128> doc;
  doc["value"] = value;
  doc["unit"] = "";
  
  String payload;
  serializeJson(doc, payload);
  
  // Sende Telemetry
  bool result = mqtt_client.publish(telemetry_topic.c_str(), payload.c_str());
  
  if (result) {
    Serial.println("📤 Telemetry gesendet: " + telemetry_topic + " = " + String(value));
  } else {
    Serial.println("❌ Fehler beim Senden der Telemetry");
  }
}

// ============================================
// ACKNOWLEDGMENT SENDEN
// ============================================

void send_ack_success(int pin, int value) {
  StaticJsonDocument<128> doc;
  doc["status"] = "success";
  JsonObject data = doc["data"].to<JsonObject>();
  data["pin"] = pin;
  data["value"] = value;
  
  String payload;
  serializeJson(doc, payload);
  
  mqtt_client.publish(ack_topic.c_str(), payload.c_str());
  Serial.println("✅ ACK gesendet: success");
}

void send_ack_error(String error_message) {
  StaticJsonDocument<128> doc;
  doc["status"] = "error";
  doc["error"] = error_message;
  
  String payload;
  serializeJson(doc, payload);
  
  mqtt_client.publish(ack_topic.c_str(), payload.c_str());
  Serial.println("❌ ACK gesendet: error - " + error_message);
}

// ============================================
// STATUS SENDEN
// ============================================

void send_status(String status) {
  mqtt_client.publish(status_topic.c_str(), status.c_str());
  Serial.println("📡 Status gesendet: " + status);
}

