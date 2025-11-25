# Arduino Setup für Knob/Slider Widget Test

## Hardware-Anforderungen

- **Raspberry Pi Pico W**, **ESP8266** (z.B. NodeMCU, Wemos D1 Mini) oder **ESP32**
- LED mit Vorwiderstand (220Ω - 1kΩ) an GPIO/PIN 16
- USB-Kabel zum Flashen und zur Stromversorgung

## Software-Anforderungen

1. **Arduino IDE** (Version 1.8.x oder neuer, empfohlen: 2.x)
2. **Board Support Packages:**
   - Für **Raspberry Pi Pico W**: Installiere "Raspberry Pi Pico/RP2040" über Board Manager
   - Für ESP8266: Installiere "ESP8266 Board" über Board Manager
   - Für ESP32: Installiere "ESP32 Board" über Board Manager
3. **Bibliotheken** (über Library Manager installieren):
   - `PubSubClient` von Nick O'Leary
   - `ArduinoJson` von Benoit Blanchon (Version 6.x)

## Installation

### 1. Bibliotheken installieren

In der Arduino IDE:
- **Sketch → Bibliothek einbinden → Bibliotheken verwalten...**
- Suche nach "PubSubClient" und installiere es
- Suche nach "ArduinoJson" und installiere es (Version 6.x)

### 2. Board auswählen

- **Werkzeuge → Board →** Wähle dein Board:
  - Für **Raspberry Pi Pico W**: "Raspberry Pi Pico W"
  - Für ESP8266: z.B. "NodeMCU 1.0 (ESP-12E Module)"
  - Für ESP32: z.B. "ESP32 Dev Module"

### 3. Konfiguration anpassen

Öffne `MC_Connect_Knob_Slider_Test.ino` und passe folgende Werte an:

```cpp
// WiFi Einstellungen
const char* ssid = "DEIN_WIFI_SSID";
const char* password = "DEIN_WIFI_PASSWORT";

// MQTT Broker Einstellungen
const char* mqtt_broker = "192.168.1.100";  // IP-Adresse deines MQTT Brokers
const int mqtt_port = 1883;

// Device ID - muss mit der Device ID in der App übereinstimmen
const char* device_id = "pico_test";  // Für Pico W (oder "arduino_test" für ESP)

// LED Konfiguration
const int LED_PIN = 16;  // GPIO 16 auf Pico W
const char* led_keyword = "led";  // Muss mit dem Widget in der App übereinstimmen
```

**Hinweis:** Das Skript erkennt automatisch das verwendete Board (Pico W, ESP8266 oder ESP32) und passt sich entsprechend an. Keine manuellen Anpassungen nötig!

### 4. Skript hochladen

**Für Raspberry Pi Pico W:**
- Halte die **BOOTSEL** Taste auf dem Pico W gedrückt
- Verbinde den Pico W per USB mit dem Computer
- Lasse die BOOTSEL Taste los
- Wähle den richtigen **Port** unter **Werkzeuge → Port**
- Klicke auf **Hochladen** (Upload)
- Beim ersten Upload: Der Pico W wird automatisch in den Bootloader-Modus versetzt

**Für ESP8266/ESP32:**
- Verbinde dein Board per USB
- Wähle den richtigen **Port** unter **Werkzeuge → Port**
- Klicke auf **Hochladen** (Upload)

## Verwendung in der App

### 1. Device erstellen

1. Öffne die MC_Connect App
2. Gehe zu **Settings → Devices**
3. Erstelle ein neues Device mit:
   - **Device ID:** `pico_test` (für Pico W) oder `arduino_test` (für ESP) - muss mit dem Code übereinstimmen
   - **MQTT Broker:** Deine Broker-IP-Adresse
   - **Port:** 1883

### 2. Widgets erstellen

#### Knob Widget:
1. Gehe zu **Dashboards**
2. Erstelle ein neues Dashboard oder wähle ein bestehendes
3. Füge ein **Knob Widget** hinzu:
   - **Title:** z.B. "LED Helligkeit"
   - **Device:** Wähle `pico_test` (oder `arduino_test` für ESP)
   - **Telemetry Keyword:** `led` (muss mit dem Code übereinstimmen)
   - **PIN:** `16`
   - **Pin Mode:** `Output`
   - **Min Value:** `0`
   - **Max Value:** `1024`
   - **Step Size:** `1` (oder höher für größere Schritte)

#### Slider Widget:
1. Füge ein **Slider Widget** hinzu:
   - **Title:** z.B. "LED Slider"
   - **Device:** Wähle `pico_test` (oder `arduino_test` für ESP)
   - **Telemetry Keyword:** `led` (muss mit dem Code übereinstimmen)
   - **PIN:** `16`
   - **Pin Mode:** `Output`
   - **Min Value:** `0`
   - **Max Value:** `1024`
   - **Step Size:** `1`

### 3. Testen

1. Verbinde die App mit dem MQTT Broker
2. Das Arduino-Board sollte automatisch verbinden (siehe Serial Monitor)
3. Bewege den Knob oder Slider in der App
4. Die LED sollte ihre Helligkeit entsprechend ändern

## Serial Monitor

Öffne den **Serial Monitor** (Werkzeuge → Serial Monitor) mit **115200 Baud**, um Debug-Informationen zu sehen:

```
=========================================
MC_Connect - Knob/Slider Test
Board: Raspberry Pi Pico W
=========================================

LED initialisiert an PIN 16
Verbinde mit WiFi: DEIN_WIFI_SSID
.....
WiFi verbunden!
IP-Adresse: 192.168.1.123
Verbinde mit MQTT Broker... verbunden!
Abonniert: device/pico_test/command
📡 Status gesendet: online
📤 Telemetry gesendet: device/pico_test/telemetry/led = 0

Setup abgeschlossen!
Bereit für Commands...

📥 Command empfangen:
Topic: device/pico_test/command
Payload: {"type":"gpio","pin":16,"value":512,"mode":"output"}

🔧 GPIO Command:
  PIN: 16
  Wert: 512
  Modus: output
✅ LED auf PIN 16 gesetzt: PWM = 512
📤 Telemetry gesendet: device/pico_test/telemetry/led = 512
✅ ACK gesendet: success
```

## Fehlerbehebung

### WiFi verbindet nicht
- Überprüfe SSID und Passwort
- Stelle sicher, dass das WiFi 2.4 GHz ist (Pico W, ESP8266/ESP32 unterstützen kein 5 GHz)
- Prüfe die Signalstärke
- **Für Pico W:** Warte etwas länger, die Verbindung kann bis zu 30 Sekunden dauern
- **Für Pico W:** Stelle sicher, dass du die **Pico W** Version verwendest (nicht den normalen Pico ohne WiFi)

### MQTT verbindet nicht
- Überprüfe die Broker-IP-Adresse
- Stelle sicher, dass der MQTT Broker läuft und erreichbar ist
- Prüfe die Firewall-Einstellungen
- Falls der Broker Authentifizierung benötigt, fülle `mqtt_username` und `mqtt_password` aus

### LED reagiert nicht
- Überprüfe die Verkabelung (LED an PIN 16 mit Vorwiderstand)
- Stelle sicher, dass `led_keyword` in App und Code übereinstimmen
- Prüfe im Serial Monitor, ob Commands ankommen
- Überprüfe, ob die Device ID in App und Code identisch ist

### PWM funktioniert nicht richtig
- **Auf Pico W:** Alle GPIO-Pins unterstützen PWM. GPIO 16 sollte funktionieren.
- **Auf ESP8266:** Nicht alle Pins unterstützen PWM. PIN 16 sollte funktionieren.
- **Auf ESP32:** Alle Pins unterstützen PWM.
- Stelle sicher, dass `analogWrite()` verwendet wird (nicht `digitalWrite()`)
- **Für Pico W:** PWM wird auf 0-255 skaliert (8-bit), die App sendet 0-1024, das Skript skaliert automatisch

## Erweiterte Konfiguration

### Mehrere LEDs testen

Du kannst mehrere LEDs an verschiedenen Pins testen, indem du:
1. Mehrere Widgets in der App erstellst (jeweils mit unterschiedlichem PIN und Keyword)
2. Den Code erweiterst, um mehrere Pins zu verwalten

### Andere PWM-Werte

Die App skaliert die Widget-Werte automatisch auf 0-1024 für PWM. Du kannst in der App einen anderen min/max Bereich einstellen (z.B. 0-100), und die App skaliert automatisch auf 0-1024.

## Unterstützte Boards

- ✅ **Raspberry Pi Pico W** (mit WiFi)
- ✅ ESP8266 (NodeMCU, Wemos D1 Mini, etc.)
- ✅ ESP32 (alle Varianten)
- ❌ Raspberry Pi Pico (ohne WiFi) - benötigt zusätzliches WiFi-Modul
- ⚠️ Standard Arduino (Uno, Nano, etc.) - benötigt zusätzliches WiFi-Shield und MQTT-Library-Anpassungen

## Raspberry Pi Pico W - Besonderheiten

- **GPIO-Nummerierung:** Der Pico W verwendet GPIO-Nummern (z.B. GPIO 16), nicht physische Pin-Nummern
- **PWM:** 8-bit PWM (0-255), das Skript skaliert automatisch von 0-1024
- **WiFi:** Kann etwas länger zum Verbinden brauchen (bis zu 30 Sekunden)
- **Upload:** Beim ersten Upload muss der Pico W im Bootloader-Modus sein (BOOTSEL-Taste gedrückt halten beim Verbinden)

