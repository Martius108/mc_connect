# MC_Connect MQTT Protocol Specification

Diese Dokumentation definiert die standardisierte MQTT-Kommunikationsstruktur für MC_Connect. **Alle angeschlossenen Microcontroller müssen diese Struktur befolgen**, um mit der App zu kommunizieren.

## Topic-Struktur

### Telemetry Topics (Device → App)
```
device/{deviceId}/telemetry/{keyword}
```

**Beispiele:**
- `device/esp01/telemetry/temperature`
- `device/pico01/telemetry/proximity`
- `device/esp32/telemetry/humidity`
- `device/esp32/telemetry/pressure`
- `device/esp01/telemetry/led` 
- `device/pico01/telemetry/relay` 
- `device/pico01/telemetry/gpio`

### Command Topics (App → Device)
```
device/{deviceId}/command
```

**Beispiel:**
- `device/pico01/command`
- `device/esp01/command`

### Status Topics (Device → App)
```
device/{deviceId}/status
```

**Payload:** `"online"` oder `"offline"` (String)

### Acknowledgment Topics (Device → App)
```
device/{deviceId}/ack
```

## Payload-Strukturen

### 1. Telemetry Payload (Standard)

**Einfaches Format:**
```json
{"value": 25.5, "unit": "°C"}
```

**Oder einfache Zahl:**
```
25.5
```

**Komplexes Format (für Sensoren mit zusätzlichen Daten):**
```json
{
  "value": 1,
  "state": "on",
  "pin": 16,
  "timestamp": 1234567890
}
```

### 2. GPIO Command (App → Device)

**Topic:** `device/{deviceId}/command`

**Payload:**
```json
{
  "type": "gpio",
  "pin": 16,
  "value": 1,
  "mode": "output"
}
```

**Felder:**
- `type`: Immer `"gpio"` für GPIO-Commands
- `pin`: PIN-Nummer (Integer)
- `value`: 
  - `0` oder `1` für digitale Ausgänge
  - `0-1024` für analoge Ausgänge (PWM)
- `mode`: Optional, `"input"` oder `"output"` (für Dokumentation)

**Beispiel für LED (PIN 16) ein:**
```json
{
  "type": "gpio",
  "pin": 16,
  "value": 1,
  "mode": "output"
}
```

**Beispiel für LED (PIN 16) aus:**
```json
{
  "type": "gpio",
  "pin": 16,
  "value": 0,
  "mode": "output"
}
```

### 2.1. Switch Widget - Bidirektionale Kommunikation

Switch Widgets in der App benötigen **bidirektionale Kommunikation**:

1. **App → Device (Command)**: Die App sendet GPIO-Commands, wenn der Benutzer den Switch umschaltet
2. **Device → App (Telemetry)**: Das Device sendet den aktuellen Switch-Status als Telemetry zurück

#### Command (App → Device)

Wenn der Benutzer einen Switch in der App umschaltet, wird ein GPIO-Command gesendet:

**Topic:** `device/{deviceId}/command`

**Payload:**
```json
{
  "type": "gpio",
  "pin": 16,
  "value": 1,
  "mode": "output"
}
```

#### Telemetry (Device → App)

Das Device sollte regelmäßig oder nach jeder Änderung den aktuellen Switch-Status als Telemetry senden:

**Topic:** `device/{deviceId}/telemetry/{keyword}`

**Beispiele für Keywords:**
- `led` - für LED-Switches
- `relay` - für Relais-Switches
- `motor` - für Motor-Switches
- `fan` - für Lüfter-Switches

**Payload (Standard-Format):**
```json
{
  "value": 1,
  "unit": ""
}
```

**Oder einfache Zahl:**
```
1
```

**Werte:**
- `0` = Switch OFF / Pin LOW
- `1` = Switch ON / Pin HIGH

**Beispiel - LED Switch (PIN 16):**

1. **App sendet Command (LED einschalten):**
   - Topic: `device/esp01/command`
   - Payload: `{"type": "gpio", "pin": 16, "value": 1, "mode": "output"}`

2. **Device setzt PIN 16 auf HIGH:**
   ```python
   pin_obj = machine.Pin(16, machine.Pin.OUT)
   pin_obj.value(1)
   ```

3. **Device sendet Telemetry (Status-Update):**
   - Topic: `device/esp01/telemetry/led`
   - Payload: `{"value": 1}` oder einfach `1`

4. **Device sendet Acknowledgment (optional, aber empfohlen):**
   - Topic: `device/esp01/ack`
   - Payload: `{"status": "success", "data": {"pin": 16, "value": 1}}`

**Wichtig für Switch Widgets:**
- Das `telemetryKeyword` wird in der App konfiguriert (z.B. "led", "relay")
- Das Device muss Telemetry-Daten mit diesem Keyword senden, damit die App den aktuellen Status anzeigen kann
- Nach jedem Command sollte das Device den neuen Status als Telemetry senden (Feedback)
- Für Input-Switches: Das Device sendet nur Telemetry, empfängt keine Commands

### 3. Sensor Command (App → Device)

**Topic:** `device/{deviceId}/command`

**Payload:**
```json
{
  "type": "sensor",
  "pin": 26,
  "action": "read",
  "config": null
}
```

**Felder:**
- `type`: Immer `"sensor"` für Sensor-Commands
- `pin`: PIN-Nummer (Integer)
- `action`: Aktion wie `"read"`, `"configure"`, etc.
- `config`: Optional, Konfigurationsdaten als JSON-String

### 4. Acknowledgment (Device → App)

**Topic:** `device/{deviceId}/ack`

**Payload (Erfolg):**
```json
{
  "command_id": "optional-id",
  "status": "success",
  "data": {
    "pin": 16,
    "value": 1
  }
}
```

**Payload (Fehler):**
```json
{
  "command_id": "optional-id",
  "status": "error",
  "error": "Invalid pin number"
}
```

## Implementierungsbeispiel (Python/MicroPython)

### Command Handler

```python
import json

def on_mqtt_command(topic, payload):
    """
    Handler für Commands von der App
    Topic: device/{deviceId}/command
    """
    try:
        # Parse JSON payload
        cmd = json.loads(payload)
        
        # Prüfe Command-Typ
        if cmd.get("type") == "gpio":
            pin = cmd.get("pin")
            value = cmd.get("value")
            mode = cmd.get("mode", "output")
            
            # Setze GPIO-Pin
            if mode == "output":
                # Setze digitalen Ausgang
                pin_obj = machine.Pin(pin, machine.Pin.OUT)
                pin_obj.value(value)
                
                # Sende Acknowledgment
                ack = {
                    "status": "success",
                    "data": {"pin": pin, "value": value}
                }
                mqtt_client.publish(f"device/{device_id}/ack", json.dumps(ack))
            else:
                # Input-Modus - nur lesen
                pin_obj = machine.Pin(pin, machine.Pin.IN)
                value = pin_obj.value()
                
                # Sende Telemetry
                telemetry = {
                    "value": value,
                    "pin": pin
                }
                mqtt_client.publish(f"device/{device_id}/telemetry/gpio_{pin}", json.dumps(telemetry))
                
        elif cmd.get("type") == "sensor":
            pin = cmd.get("pin")
            action = cmd.get("action")
            
            if action == "read":
                # Lese Sensor-Wert
                # ... Sensor-Logik ...
                pass
                
    except Exception as e:
        # Sende Fehler-Acknowledgment
        ack = {
            "status": "error",
            "error": str(e)
        }
        mqtt_client.publish(f"device/{device_id}/ack", json.dumps(ack))
```

### Telemetry Sender

```python
def send_telemetry(keyword, value, unit=""):
    """
    Sendet Telemetry-Daten an die App
    """
    topic = f"device/{device_id}/telemetry/{keyword}"
    
    # Standard-Format
    payload = {
        "value": value,
        "unit": unit
    }
    
    mqtt_client.publish(topic, json.dumps(payload))
```

### Switch Widget - Vollständiges Beispiel

```python
import json
import machine
from umqtt.simple import MQTTClient

# Konfiguration
device_id = "esp01"
led_pin = 16
led_keyword = "led"  # Muss mit dem telemetryKeyword in der App übereinstimmen

# GPIO initialisieren
led = machine.Pin(led_pin, machine.Pin.OUT)
led.value(0)  # Initial OFF

def on_mqtt_command(topic, payload):
    """
    Handler für Commands von der App
    """
    try:
        cmd = json.loads(payload)
        
        if cmd.get("type") == "gpio":
            pin = cmd.get("pin")
            value = cmd.get("value")
            
            # Prüfe ob es unser LED-Pin ist
            if pin == led_pin:
                # Setze PIN
                led.value(value)
                
                # Sende sofort Telemetry mit neuem Status (Feedback)
                send_switch_telemetry(value)
                
                # Sende Acknowledgment
                ack = {
                    "status": "success",
                    "data": {"pin": pin, "value": value}
                }
                mqtt_client.publish(f"device/{device_id}/ack", json.dumps(ack))
                
    except Exception as e:
        ack = {
            "status": "error",
            "error": str(e)
        }
        mqtt_client.publish(f"device/{device_id}/ack", json.dumps(ack))

def send_switch_telemetry(value):
    """
    Sendet den aktuellen Switch-Status als Telemetry
    """
    topic = f"device/{device_id}/telemetry/{led_keyword}"
    payload = {"value": value}
    mqtt_client.publish(topic, json.dumps(payload))
    print(f"📤 Sent switch telemetry: {topic} = {value}")

# Regelmäßig Status senden (z.B. alle 5 Sekunden oder nach Änderung)
def periodic_status_update():
    """
    Sendet periodisch den aktuellen Status (optional, für Robustheit)
    """
    current_value = led.value()
    send_switch_telemetry(current_value)

# MQTT Callback registrieren
mqtt_client.set_callback(on_mqtt_command)
mqtt_client.subscribe(f"device/{device_id}/command")

# Initialen Status senden
send_switch_telemetry(led.value())
```

## Wichtige Hinweise

1. **Einheitliches Topic:** Alle Commands gehen an `device/{deviceId}/command` - nicht an `/gpio`, `/cmd` oder andere Topics
2. **Standardisiertes Format:** Alle Commands haben ein `type`-Feld, das den Command-Typ definiert
3. **Telemetry Keywords:** Werden in der App konfiguriert und sollten konsistent verwendet werden
4. **Acknowledgment:** Devices sollten immer ein ACK senden, um den Erfolg/Fehler zu bestätigen
5. **Switch Widgets:** Benötigen bidirektionale Kommunikation:
   - Empfangen Commands über `device/{deviceId}/command`
   - Senden Status-Updates über `device/{deviceId}/telemetry/{keyword}`
   - Das `telemetryKeyword` muss in der App konfiguriert werden (z.B. "led", "relay")
   - Nach jedem Command sollte der neue Status als Telemetry gesendet werden (Feedback)

## Migration von alter Struktur

Wenn Sie bereits einen Microcontroller-Code haben, der andere Topics verwendet:

**Alt:**
- Topic: `device/{id}/gpio` oder `device/{id}/cmd`
- Payload: `{"target": "led_ext", "pin": 16, "value": 1}`

**Neu:**
- Topic: `device/{id}/command`
- Payload: `{"type": "gpio", "pin": 16, "value": 1, "mode": "output"}`

Die App verwendet jetzt die neue standardisierte Struktur. Bitte passen Sie Ihren Microcontroller-Code entsprechend an.

---

## Widget-Übersicht

Die MC_Connect App unterstützt verschiedene Widget-Typen für die Visualisierung und Steuerung von Microcontroller-Daten. Jedes Widget hat spezifische Anforderungen an die MQTT-Kommunikation.

### Widget-Kategorien

**Eingabe-Widgets (App → Device):**
- **Switch** - Toggle-Schalter für digitale Ausgänge
- **Slider** - Regler für PWM/Analog-Ausgänge (0-1024)
- **Button** - Tastendruck mit konfigurierbarer Dauer

**Ausgabe-Widgets (Device → App):**
- **Value** - Einfache Wertanzeige
- **Gauge** - Kreisdiagramm-Anzeige
- **Progress Bar** - Balken-Anzeige
- **Sensor Analog** - Analog-Sensor mit Wertanzeige
- **Sensor Binary** - Digital-Sensor mit Status-Anzeige
- **Climate** - Kombiniertes Widget für Temperatur und Luftfeuchtigkeit
- **2 x Value** - Zwei Werte nebeneinander

---

## Detaillierte Widget-Dokumentation

### 1. Value Widget (Ausgabe)

**Zweck:** Zeigt einen einzelnen numerischen Wert an.

**Telemetry (Device → App):**
- **Topic:** `device/{deviceId}/telemetry/{keyword}`
- **Payload:**
  ```json
  {"value": 25.5, "unit": "°C"}
  ```
  Oder einfache Zahl: `25.5`

**Beispiel:**
```python
# Temperatur-Wert senden
send_telemetry("temperature", 23.5, "°C")

# Oder einfaches Format
mqtt_client.publish(
    f"device/{device_id}/telemetry/temperature",
    "23.5"
)
```

**Konfiguration in App:**
- `telemetryKeyword`: z.B. "temperature", "voltage", "current"
- `unit`: Optional, z.B. "°C", "V", "mA"

---

### 2. Gauge Widget (Ausgabe)

**Zweck:** Zeigt einen Wert als Kreisdiagramm (0-100% oder min-max Bereich).

**Telemetry (Device → App):**
- **Topic:** `device/{deviceId}/telemetry/{keyword}`
- **Payload:**
  ```json
  {"value": 75.5, "unit": "%"}
  ```

**Wichtig:**
- Der Wert wird basierend auf `minValue` und `maxValue` (in App konfiguriert) normalisiert
- Wenn min/max nicht gesetzt sind, wird 0-100 angenommen

**Beispiel:**
```python
# Batterie-Ladestand (0-100%)
send_telemetry("battery", 85.0, "%")

# Spannung mit min/max (0-5V)
send_telemetry("voltage", 3.7, "V")
```

**Konfiguration in App:**
- `telemetryKeyword`: z.B. "battery", "voltage", "pressure"
- `minValue`: Minimum-Wert (optional, default: 0)
- `maxValue`: Maximum-Wert (optional, default: 100)
- `unit`: Optional

---

### 3. Progress Bar Widget (Ausgabe)

**Zweck:** Zeigt einen Wert als horizontalen Fortschrittsbalken.

**Telemetry (Device → App):**
- **Topic:** `device/{deviceId}/telemetry/{keyword}`
- **Payload:**
  ```json
  {"value": 60.0, "unit": "%"}
  ```

**Beispiel:**
```python
# Fortschrittsanzeige
send_telemetry("progress", 60.0, "%")

# Sensor-Wert mit Bereich
send_telemetry("light", 450.0, "lux")
```

**Konfiguration in App:**
- `telemetryKeyword`: z.B. "progress", "light", "distance"
- `minValue`: Minimum-Wert (optional, default: 0)
- `maxValue`: Maximum-Wert (optional, default: 100)
- `unit`: Optional

---

### 4. Switch Widget (Eingabe/Ausgabe - Bidirektional)

**Zweck:** Toggle-Schalter für digitale GPIO-Ausgänge.

**Command (App → Device):**
- **Topic:** `device/{deviceId}/command`
- **Payload:**
  ```json
  {
    "type": "gpio",
    "pin": 16,
    "value": 1,
    "mode": "output"
  }
  ```
  - `value`: `0` = OFF, `1` = ON

**Telemetry (Device → App):**
- **Topic:** `device/{deviceId}/telemetry/{keyword}`
- **Payload:**
  ```json
  {"value": 1}
  ```
  Oder einfache Zahl: `1`

**Wichtig:**
- Nach jedem Command sollte das Device den neuen Status als Telemetry senden (Feedback)
- Das `telemetryKeyword` wird in der App konfiguriert (z.B. "led", "relay")

**Vollständiges Beispiel:**
```python
import json
import machine
from umqtt.simple import MQTTClient

device_id = "esp01"
led_pin = 16
led_keyword = "led"  # Muss mit App-Konfiguration übereinstimmen

# GPIO initialisieren
led = machine.Pin(led_pin, machine.Pin.OUT)
led.value(0)

def on_mqtt_command(topic, payload):
    """Handler für Commands von der App"""
    try:
        cmd = json.loads(payload)
        
        if cmd.get("type") == "gpio":
            pin = cmd.get("pin")
            value = cmd.get("value")
            
            if pin == led_pin:
                # Setze PIN
                led.value(value)
                
                # Sende sofort Feedback als Telemetry
                send_switch_telemetry(value)
                
                # Sende Acknowledgment
                ack = {
                    "status": "success",
                    "data": {"pin": pin, "value": value}
                }
                mqtt_client.publish(
                    f"device/{device_id}/ack",
                    json.dumps(ack)
                )
    except Exception as e:
        ack = {"status": "error", "error": str(e)}
        mqtt_client.publish(
            f"device/{device_id}/ack",
            json.dumps(ack)
        )

def send_switch_telemetry(value):
    """Sendet Switch-Status als Telemetry"""
    topic = f"device/{device_id}/telemetry/{led_keyword}"
    payload = {"value": value}
    mqtt_client.publish(topic, json.dumps(payload))

# MQTT Callback registrieren
mqtt_client.set_callback(on_mqtt_command)
mqtt_client.subscribe(f"device/{device_id}/command")

# Initialen Status senden
send_switch_telemetry(led.value())
```

**Konfiguration in App:**
- `pin`: GPIO-PIN-Nummer
- `pinMode`: "Output" für steuerbare Switches
- `telemetryKeyword`: z.B. "led", "relay", "motor", "fan"

---

### 5. Slider Widget (Eingabe/Ausgabe - Bidirektional)

**Zweck:** Regler für PWM/Analog-Ausgänge (0-1024).

**Command (App → Device):**
- **Topic:** `device/{deviceId}/command`
- **Payload:**
  ```json
  {
    "type": "gpio",
    "pin": 18,
    "value": 512,
    "mode": "output"
  }
  ```
  - `value`: `0-1024` für PWM-Werte

**Telemetry (Device → App):**
- **Topic:** `device/{deviceId}/telemetry/{keyword}`
- **Payload:**
  ```json
  {"value": 512}
  ```
  Oder einfache Zahl: `512`

**Wichtig:**
- Nach jedem Command sollte das Device den neuen PWM-Wert als Telemetry senden (Feedback)
- Der Wert wird in der App auf den konfigurierten min/max Bereich skaliert

**Beispiel:**
```python
import json
import machine
from umqtt.simple import MQTTClient

device_id = "esp01"
pwm_pin = 18
pwm_keyword = "brightness"  # Muss mit App-Konfiguration übereinstimmen

# PWM initialisieren
pwm = machine.PWM(machine.Pin(pwm_pin))
pwm.freq(1000)  # 1kHz
pwm.duty(0)  # Initial 0%

def on_mqtt_command(topic, payload):
    """Handler für Commands von der App"""
    try:
        cmd = json.loads(payload)
        
        if cmd.get("type") == "gpio":
            pin = cmd.get("pin")
            value = cmd.get("value")  # 0-1024
            
            if pin == pwm_pin:
                # Setze PWM-Wert
                pwm.duty(value)
                
                # Sende sofort Feedback als Telemetry
                send_slider_telemetry(value)
                
                # Sende Acknowledgment
                ack = {
                    "status": "success",
                    "data": {"pin": pin, "value": value}
                }
                mqtt_client.publish(
                    f"device/{device_id}/ack",
                    json.dumps(ack)
                )
    except Exception as e:
        ack = {"status": "error", "error": str(e)}
        mqtt_client.publish(
            f"device/{device_id}/ack",
            json.dumps(ack)
        )

def send_slider_telemetry(value):
    """Sendet aktuellen PWM-Wert als Telemetry"""
    topic = f"device/{device_id}/telemetry/{pwm_keyword}"
    payload = {"value": value}
    mqtt_client.publish(topic, json.dumps(payload))

# MQTT Callback registrieren
mqtt_client.set_callback(on_mqtt_command)
mqtt_client.subscribe(f"device/{device_id}/command")

# Initialen Wert senden
send_slider_telemetry(0)
```

**Konfiguration in App:**
- `pin`: GPIO-PIN-Nummer (PWM-fähig)
- `pinMode`: "Output"
- `telemetryKeyword`: z.B. "brightness", "speed", "volume"
- `minValue`: Minimum-Wert (optional, default: 0)
- `maxValue`: Maximum-Wert (optional, default: 1024)

---

### 6. Button Widget (Eingabe/Ausgabe - Bidirektional)

**Zweck:** Tastendruck mit konfigurierbarer Dauer für zuverlässige Schaltvorgänge.

**Command (App → Device):**
Die App sendet **zwei Commands** in schneller Folge:

1. **HIGH-Command:**
   ```json
   {
     "type": "gpio",
     "pin": 16,
     "value": 1,
     "mode": "output"
   }
   ```

2. **LOW-Command (nach konfigurierter Dauer):**
   ```json
   {
     "type": "gpio",
     "pin": 16,
     "value": 0,
     "mode": "output"
   }
   ```

**Telemetry (Device → App):**
- **Topic:** `device/{deviceId}/telemetry/{keyword}`
- **Payload:**
  ```json
  {"value": 1}
  ```
  - `1` = Button gedrückt (HIGH)
  - `0` = Button nicht gedrückt (LOW)

**Wichtig:**
- Die App sendet automatisch HIGH, wartet die konfigurierte Dauer (Standard: 100ms), dann LOW
- Das Device sollte nach jedem Command den aktuellen Status als Telemetry senden
- Die Dauer ist in der App konfigurierbar (in Millisekunden)

**Beispiel:**
```python
import json
import machine
from umqtt.simple import MQTTClient
import time

device_id = "esp01"
button_pin = 16
button_keyword = "button"  # Muss mit App-Konfiguration übereinstimmen

# GPIO initialisieren
button_output = machine.Pin(button_pin, machine.Pin.OUT)
button_output.value(0)  # Initial LOW

def on_mqtt_command(topic, payload):
    """Handler für Commands von der App"""
    try:
        cmd = json.loads(payload)
        
        if cmd.get("type") == "gpio":
            pin = cmd.get("pin")
            value = cmd.get("value")
            
            if pin == button_pin:
                # Setze PIN
                button_output.value(value)
                
                # Sende sofort Feedback als Telemetry
                send_button_telemetry(value)
                
                # Sende Acknowledgment
                ack = {
                    "status": "success",
                    "data": {"pin": pin, "value": value}
                }
                mqtt_client.publish(
                    f"device/{device_id}/ack",
                    json.dumps(ack)
                )
    except Exception as e:
        ack = {"status": "error", "error": str(e)}
        mqtt_client.publish(
            f"device/{device_id}/ack",
            json.dumps(ack)
        )

def send_button_telemetry(value):
    """Sendet Button-Status als Telemetry"""
    topic = f"device/{device_id}/telemetry/{button_keyword}"
    payload = {"value": value}
    mqtt_client.publish(topic, json.dumps(payload))

# MQTT Callback registrieren
mqtt_client.set_callback(on_mqtt_command)
mqtt_client.subscribe(f"device/{device_id}/command")

# Initialen Status senden
send_button_telemetry(0)
```

**Konfiguration in App:**
- `pin`: GPIO-PIN-Nummer
- `pinMode`: "Output"
- `telemetryKeyword`: z.B. "button", "reset", "trigger"
- `buttonDuration`: Dauer in Millisekunden (Standard: 100ms)

---

### 7. Sensor Analog Widget (Ausgabe)

**Zweck:** Zeigt analoge Sensor-Werte an (z.B. Potentiometer, Lichtsensor).

**Telemetry (Device → App):**
- **Topic:** `device/{deviceId}/telemetry/{keyword}`
- **Payload:**
  ```json
  {"value": 512.5, "unit": ""}
  ```
  Oder einfache Zahl: `512.5`

**Beispiel:**
```python
import machine
import time

# Analog-Sensor am ADC-Pin
adc = machine.ADC(machine.Pin(26))
adc.atten(machine.ADC.ATTN_11DB)  # 0-3.3V

def read_analog_sensor():
    """Liest analogen Sensor-Wert"""
    # ADC gibt 0-4095 zurück (12-bit)
    raw_value = adc.read()
    
    # Optional: Umrechnung in physikalische Einheit
    voltage = (raw_value / 4095) * 3.3
    
    # Sende als Telemetry
    send_telemetry("potentiometer", raw_value, "")
    # Oder mit Spannung:
    # send_telemetry("voltage", voltage, "V")

# Regelmäßig lesen und senden
while True:
    read_analog_sensor()
    time.sleep(1)  # Alle 1 Sekunde
```

**Konfiguration in App:**
- `pin`: GPIO-PIN-Nummer (ADC-Pin)
- `sensorType`: "Analog"
- `telemetryKeyword`: z.B. "potentiometer", "light", "voltage"
- `minValue`: Minimum-Wert (optional)
- `maxValue`: Maximum-Wert (optional)
- `invertedLogic`: Optional, invertiert die Logik

---

### 8. Sensor Binary Widget (Ausgabe)

**Zweck:** Zeigt digitalen Sensor-Status an (z.B. Bewegungsmelder, Taster).

**Telemetry (Device → App):**
- **Topic:** `device/{deviceId}/telemetry/{keyword}`
- **Payload:**
  ```json
  {"value": 1}
  ```
  Oder einfache Zahl: `1`
  - `0` = LOW / Inaktiv
  - `1` = HIGH / Aktiv

**Beispiel:**
```python
import machine
import time

# Digital-Sensor (z.B. Bewegungsmelder)
motion_sensor = machine.Pin(14, machine.Pin.IN, machine.Pin.PULL_UP)
motion_keyword = "motion"

def read_binary_sensor():
    """Liest digitalen Sensor-Wert"""
    value = motion_sensor.value()
    
    # Sende als Telemetry
    send_telemetry(motion_keyword, value, "")

# Regelmäßig lesen und senden
while True:
    read_binary_sensor()
    time.sleep(0.5)  # Alle 0.5 Sekunden
```

**Konfiguration in App:**
- `pin`: GPIO-PIN-Nummer
- `sensorType`: "Binary"
- `telemetryKeyword`: z.B. "motion", "door", "button"
- `minValue`: Threshold für LOW (optional, default: 0)
- `maxValue`: Threshold für HIGH (optional, default: 1)
- `invertedLogic`: Optional, invertiert die Logik (LOW = aktiv)

---

### 9. Climate Widget (Ausgabe)

**Zweck:** Kombiniertes Widget für Temperatur und Luftfeuchtigkeit.

**Telemetry (Device → App):**
Zwei separate Telemetry-Nachrichten:

1. **Temperatur:**
   - **Topic:** `device/{deviceId}/telemetry/temperature`
   - **Payload:**
     ```json
     {"value": 23.5, "unit": "°C"}
     ```

2. **Luftfeuchtigkeit:**
   - **Topic:** `device/{deviceId}/telemetry/humidity`
   - **Payload:**
     ```json
     {"value": 65.0, "unit": "%"}
     ```

**Beispiel:**
```python
import machine
import dht
import time

# DHT22 Sensor
dht_sensor = dht.DHT22(machine.Pin(4))

def read_climate_sensor():
    """Liest Temperatur und Luftfeuchtigkeit"""
    try:
        dht_sensor.measure()
        temp = dht_sensor.temperature()
        humidity = dht_sensor.humidity()
        
        # Sende beide Werte
        send_telemetry("temperature", temp, "°C")
        send_telemetry("humidity", humidity, "%")
        
    except Exception as e:
        print(f"Error reading DHT: {e}")

# Regelmäßig lesen und senden
while True:
    read_climate_sensor()
    time.sleep(2)  # Alle 2 Sekunden (DHT22 braucht Zeit)
```

**Konfiguration in App:**
- `telemetryKeyword`: Immer "temperature"
- `secondaryTelemetryKeyword`: Immer "humidity"
- `temperatureMinValue`: Optional, Minimum-Temperatur
- `temperatureMaxValue`: Optional, Maximum-Temperatur
- `humidityMinValue`: Optional, Minimum-Luftfeuchtigkeit
- `humidityMaxValue`: Optional, Maximum-Luftfeuchtigkeit

---

### 10. 2 x Value Widget (Ausgabe)

**Zweck:** Zeigt zwei Werte nebeneinander an.

**Telemetry (Device → App):**
Zwei separate Telemetry-Nachrichten:

1. **Erster Wert:**
   - **Topic:** `device/{deviceId}/telemetry/{keyword}`
   - **Payload:**
     ```json
     {"value": 12.5, "unit": "V"}
     ```

2. **Zweiter Wert:**
   - **Topic:** `device/{deviceId}/telemetry/{secondaryKeyword}`
   - **Payload:**
     ```json
     {"value": 2.3, "unit": "A"}
     ```

**Beispiel:**
```python
# Spannung und Strom senden
send_telemetry("voltage", 12.5, "V")
send_telemetry("current", 2.3, "A")
```

**Konfiguration in App:**
- `telemetryKeyword`: Erster Wert, z.B. "voltage"
- `secondaryTelemetryKeyword`: Zweiter Wert, z.B. "current"
- `unit`: Einheit für ersten Wert
- `secondaryUnit`: Einheit für zweiten Wert

---

## Vollständiges Implementierungsbeispiel

Hier ist ein vollständiges Beispiel, das mehrere Widget-Typen unterstützt:

```python
import json
import machine
import time
from umqtt.simple import MQTTClient

# Konfiguration
device_id = "esp01"
mqtt_broker = "192.168.1.100"
mqtt_port = 1883

# GPIO-Pins konfigurieren
led_pin = 16
pwm_pin = 18
button_pin = 19
temp_sensor_pin = 4
motion_sensor_pin = 14

# GPIO initialisieren
led = machine.Pin(led_pin, machine.Pin.OUT)
led.value(0)

pwm = machine.PWM(machine.Pin(pwm_pin))
pwm.freq(1000)
pwm.duty(0)

button_output = machine.Pin(button_pin, machine.Pin.OUT)
button_output.value(0)

motion_sensor = machine.Pin(motion_sensor_pin, machine.Pin.IN, machine.Pin.PULL_UP)

# MQTT Client initialisieren
mqtt_client = MQTTClient(device_id, mqtt_broker, mqtt_port)
mqtt_client.connect()

def send_telemetry(keyword, value, unit=""):
    """Sendet Telemetry-Daten an die App"""
    topic = f"device/{device_id}/telemetry/{keyword}"
    payload = {"value": value, "unit": unit}
    mqtt_client.publish(topic, json.dumps(payload))
    print(f"📤 {topic} = {value} {unit}")

def on_mqtt_command(topic, payload):
    """Handler für Commands von der App"""
    try:
        cmd = json.loads(payload)
        
        if cmd.get("type") == "gpio":
            pin = cmd.get("pin")
            value = cmd.get("value")
            mode = cmd.get("mode", "output")
            
            if mode == "output":
                # Setze GPIO-Pin
                pin_obj = machine.Pin(pin, machine.Pin.OUT)
                pin_obj.value(value)
                
                # Sende Feedback basierend auf PIN
                if pin == led_pin:
                    send_telemetry("led", value, "")
                elif pin == pwm_pin:
                    send_telemetry("brightness", value, "")
                elif pin == button_pin:
                    send_telemetry("button", value, "")
                
                # Sende Acknowledgment
                ack = {
                    "status": "success",
                    "data": {"pin": pin, "value": value}
                }
                mqtt_client.publish(
                    f"device/{device_id}/ack",
                    json.dumps(ack)
                )
                
    except Exception as e:
        ack = {"status": "error", "error": str(e)}
        mqtt_client.publish(
            f"device/{device_id}/ack",
            json.dumps(ack)
        )

# MQTT Callback registrieren
mqtt_client.set_callback(on_mqtt_command)
mqtt_client.subscribe(f"device/{device_id}/command")

# Status senden
mqtt_client.publish(
    f"device/{device_id}/status",
    "online"
)

# Initiale Telemetry senden
send_telemetry("led", 0, "")
send_telemetry("brightness", 0, "")
send_telemetry("button", 0, "")
send_telemetry("motion", motion_sensor.value(), "")

# Hauptschleife
while True:
    # MQTT-Nachrichten verarbeiten
    mqtt_client.check_msg()
    
    # Sensoren lesen und senden
    motion_value = motion_sensor.value()
    send_telemetry("motion", motion_value, "")
    
    # Beispiel: Temperatur simulieren (ersetzt durch echten Sensor)
    # temp = read_temperature_sensor()
    # send_telemetry("temperature", temp, "°C")
    
    time.sleep(1)  # Alle 1 Sekunde
```

---

## Zusammenfassung: Widget-Anforderungen

| Widget | Typ | Command | Telemetry | Besonderheiten |
|--------|-----|---------|-----------|----------------|
| **Value** | Ausgabe | ❌ | ✅ | Einfacher Wert |
| **Gauge** | Ausgabe | ❌ | ✅ | Wert mit min/max Bereich |
| **Progress Bar** | Ausgabe | ❌ | ✅ | Wert mit min/max Bereich |
| **Switch** | Bidirektional | ✅ | ✅ | Benötigt Feedback nach Command |
| **Slider** | Bidirektional | ✅ | ✅ | PWM-Werte (0-1024), benötigt Feedback |
| **Button** | Bidirektional | ✅ | ✅ | Zwei Commands (HIGH → LOW), benötigt Feedback |
| **Sensor Analog** | Ausgabe | ❌ | ✅ | Analog-Wert (0-4095 oder physikalische Einheit) |
| **Sensor Binary** | Ausgabe | ❌ | ✅ | Digital-Wert (0 oder 1) |
| **Climate** | Ausgabe | ❌ | ✅ | Zwei Keywords: temperature + humidity |
| **2 x Value** | Ausgabe | ❌ | ✅ | Zwei Keywords: keyword + secondaryKeyword |

---

## Wichtige Best Practices

1. **Feedback senden:** Bei bidirektionalen Widgets (Switch, Slider, Button) immer nach jedem Command den neuen Status als Telemetry senden
2. **Konsistente Keywords:** Verwenden Sie konsistente Telemetry-Keywords, die in der App konfiguriert werden
3. **Acknowledgment:** Senden Sie immer ein ACK nach Commands (Erfolg oder Fehler)
4. **Regelmäßige Updates:** Senden Sie Telemetry regelmäßig, auch wenn sich der Wert nicht ändert (für Robustheit)
5. **Einheiten:** Verwenden Sie die korrekten Einheiten (werden in der App konfiguriert, aber sollten konsistent sein)
6. **Wertebereich:** Respektieren Sie min/max Werte, die in der App konfiguriert werden (für Gauge, Progress Bar, Slider)

