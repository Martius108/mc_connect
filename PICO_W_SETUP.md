# Raspberry Pi Pico W Setup für Knob/Slider Widget Test

## Hardware-Anforderungen

- **Raspberry Pi Pico W**
- LED mit Vorwiderstand (220Ω - 1kΩ) an GPIO 16
- USB-Kabel zum Flashen und zur Stromversorgung

## Software-Anforderungen

1. **MicroPython** auf dem Pico W installiert
   - Lade die neueste MicroPython-Firmware von [micropython.org](https://micropython.org/download/rp2-pico-w/)
   - Installiere sie auf dem Pico W (siehe Installationsanleitung unten)

2. **Thonny IDE** (empfohlen) oder ein anderer MicroPython-Editor
   - Download: [thonny.org](https://thonny.org/)

## Installation

### 1. MicroPython auf Pico W installieren

1. **Firmware herunterladen:**
   - Gehe zu [micropython.org/download/rp2-pico-w/](https://micropython.org/download/rp2-pico-w/)
   - Lade die neueste `.uf2` Datei herunter

2. **Firmware installieren:**
   - Halte die **BOOTSEL** Taste auf dem Pico W gedrückt
   - Verbinde den Pico W per USB mit dem Computer
   - Lasse die BOOTSEL Taste los
   - Der Pico W erscheint als USB-Laufwerk
   - Ziehe die `.uf2` Datei auf das USB-Laufwerk
   - Der Pico W startet automatisch neu mit MicroPython

### 2. Thonny IDE einrichten

1. **Thonny installieren und öffnen**
2. **Interpreter auswählen:**
   - **Werkzeuge → Interpreter**
   - Wähle "MicroPython (Raspberry Pi Pico)"
   - Wähle den richtigen Port (z.B. `/dev/ttyACM0` auf Linux oder `COM3` auf Windows)

3. **Bibliotheken prüfen:**
   - Die benötigten Module (`umqtt.simple`, `ujson`) sollten bereits in MicroPython enthalten sein
   - Falls `umqtt.simple` fehlt, lade es manuell herunter und kopiere es auf den Pico W

### 3. Skript auf Pico W hochladen

1. **Öffne `MC_Connect_Knob_Slider_Test.py` in Thonny**
2. **Konfiguration anpassen:**
   - Bearbeite die Konfigurationsvariablen am Anfang der Datei:

```python
# WiFi Einstellungen
WIFI_SSID = "DEIN_WIFI_SSID"
WIFI_PASSWORD = "DEIN_WIFI_PASSWORT"

# MQTT Broker Einstellungen
MQTT_BROKER = "192.168.1.100"  # IP-Adresse deines MQTT Brokers
MQTT_PORT = 1883
MQTT_USERNAME = ""  # Optional: MQTT Benutzername
MQTT_PASSWORD = ""  # Optional: MQTT Passwort

# Device ID - muss mit der Device ID in der App übereinstimmen
DEVICE_ID = "pico_test"

# LED Konfiguration
LED_PIN = 16  # GPIO PIN für die LED
LED_KEYWORD = "led"  # Telemetry Keyword - muss mit dem Widget in der App übereinstimmen
```

3. **Skript speichern:**
   - **Datei → Speichern unter**
   - Wähle "Raspberry Pi Pico" als Ziel
   - Speichere als `main.py` (wird beim Start automatisch ausgeführt)
   - Oder speichere als `MC_Connect_Knob_Slider_Test.py` und starte es manuell

4. **Skript ausführen:**
   - Klicke auf den **Grünen Play-Button** (▶️) in Thonny
   - Oder drücke **F5**

### 4. Automatischer Start (optional)

Wenn du das Skript als `main.py` speicherst, wird es automatisch beim Start des Pico W ausgeführt. Dies ist praktisch für den produktiven Einsatz.

## Verwendung in der App

### 1. Device erstellen

1. Öffne die MC_Connect App
2. Gehe zu **Settings → Devices**
3. Erstelle ein neues Device mit:
   - **Device ID:** `pico_test` (muss mit dem Code übereinstimmen)
   - **MQTT Broker:** Deine Broker-IP-Adresse
   - **Port:** 1883

### 2. Widgets erstellen

#### Knob Widget:
1. Gehe zu **Dashboards**
2. Erstelle ein neues Dashboard oder wähle ein bestehendes
3. Füge ein **Knob Widget** hinzu:
   - **Title:** z.B. "LED Helligkeit"
   - **Device:** Wähle `pico_test`
   - **Telemetry Keyword:** `led` (muss mit dem Code übereinstimmen)
   - **PIN:** `16`
   - **Pin Mode:** `Output`
   - **Min Value:** `0`
   - **Max Value:** `1024`
   - **Step Size:** `1` (oder höher für größere Schritte)

#### Slider Widget:
1. Füge ein **Slider Widget** hinzu:
   - **Title:** z.B. "LED Slider"
   - **Device:** Wähle `pico_test`
   - **Telemetry Keyword:** `led` (muss mit dem Code übereinstimmen)
   - **PIN:** `16`
   - **Pin Mode:** `Output`
   - **Min Value:** `0`
   - **Max Value:** `1024`
   - **Step Size:** `1`

### 3. Testen

1. Verbinde die App mit dem MQTT Broker
2. Der Pico W sollte automatisch verbinden (siehe Thonny Shell)
3. Bewege den Knob oder Slider in der App
4. Die LED sollte ihre Helligkeit entsprechend ändern

## Serial Monitor / Thonny Shell

In Thonny siehst du die Debug-Ausgaben direkt in der Shell:

```
========================================
MC_Connect - Knob/Slider Test
Raspberry Pi Pico W
========================================

Verbinde mit WiFi: DEIN_WIFI_SSID
.....
✅ WiFi verbunden!
IP-Adresse: 192.168.1.123
LED initialisiert an PIN 16
Verbinde mit MQTT Broker... verbunden!
Abonniert: device/pico_test/command
📡 Status gesendet: online
📤 Telemetry gesendet: device/pico_test/telemetry/led = 0

✅ Setup abgeschlossen!
Bereit für Commands...

📥 Command empfangen:
Topic: device/pico_test/command
Payload: {"type":"gpio","pin":16,"value":512,"mode":"output"}

🔧 GPIO Command:
  PIN: 16
  Wert: 512
  Modus: output
✅ LED auf PIN 16 gesetzt: PWM = 512 (duty = 32767)
📤 Telemetry gesendet: device/pico_test/telemetry/led = 512
✅ ACK gesendet: success
```

## Fehlerbehebung

### MicroPython installiert nicht
- Stelle sicher, dass du die **Pico W** Firmware (nicht Pico) heruntergeladen hast
- Der Pico W hat WiFi, der normale Pico nicht
- Halte BOOTSEL beim Verbinden gedrückt

### WiFi verbindet nicht
- Überprüfe SSID und Passwort
- Stelle sicher, dass das WiFi 2.4 GHz ist (Pico W unterstützt kein 5 GHz)
- Prüfe die Signalstärke
- Warte länger (manchmal braucht der Pico W etwas länger zum Verbinden)

### MQTT verbindet nicht
- Überprüfe die Broker-IP-Adresse
- Stelle sicher, dass der MQTT Broker läuft und erreichbar ist
- Prüfe die Firewall-Einstellungen
- Falls der Broker Authentifizierung benötigt, fülle `MQTT_USERNAME` und `MQTT_PASSWORD` aus
- Prüfe, ob `umqtt.simple` verfügbar ist (sollte in MicroPython enthalten sein)

### LED reagiert nicht
- Überprüfe die Verkabelung:
  - LED Anode (+) → Vorwiderstand (220Ω-1kΩ) → GPIO 16
  - LED Kathode (-) → GND
- Stelle sicher, dass `LED_KEYWORD` in App und Code übereinstimmen
- Prüfe in Thonny Shell, ob Commands ankommen
- Überprüfe, ob die Device ID in App und Code identisch ist
- Teste den GPIO-Pin mit einem einfachen Blink-Skript

### PWM funktioniert nicht richtig
- Alle GPIO-Pins auf dem Pico W unterstützen PWM
- Stelle sicher, dass `PWM` und `duty_u16()` verwendet werden
- Der Pico W verwendet 16-bit PWM (0-65535), das Skript skaliert automatisch von 0-1024

### Skript startet nicht automatisch
- Stelle sicher, dass die Datei `main.py` heißt (nicht `MC_Connect_Knob_Slider_Test.py`)
- Prüfe, ob es keine Syntax-Fehler gibt (Thonny zeigt diese an)
- Starte das Skript manuell in Thonny, um Fehler zu sehen

## GPIO-Pin Belegung

Der Raspberry Pi Pico W hat viele GPIO-Pins. Für dieses Projekt verwenden wir:
- **GPIO 16** für die LED (PWM-fähig)

**Wichtig:** Der Pico W verwendet **GPIO-Nummern**, nicht physische Pin-Nummern. GPIO 16 entspricht physischem Pin 21.

## Erweiterte Konfiguration

### Mehrere LEDs testen

Du kannst mehrere LEDs an verschiedenen GPIO-Pins testen, indem du:
1. Mehrere Widgets in der App erstellst (jeweils mit unterschiedlichem PIN und Keyword)
2. Den Code erweiterst, um mehrere PWM-Objekte zu verwalten

### Andere PWM-Werte

Die App skaliert die Widget-Werte automatisch auf 0-1024 für PWM. Du kannst in der App einen anderen min/max Bereich einstellen (z.B. 0-100), und die App skaliert automatisch auf 0-1024. Das Skript skaliert dann intern auf 0-65535 für den Pico W.

### Umqtt.simple fehlt

Falls `umqtt.simple` nicht in deiner MicroPython-Installation enthalten ist:

1. Lade `umqtt` von [GitHub](https://github.com/micropython/micropython-lib/tree/master/micropython/umqtt.simple) herunter
2. Kopiere `umqtt/simple.py` auf den Pico W
3. Oder installiere es über `mip` (MicroPython Package Manager):

```python
import mip
mip.install("umqtt.simple")
```

## Unterstützte Hardware

- ✅ Raspberry Pi Pico W (mit WiFi)
- ❌ Raspberry Pi Pico (ohne WiFi - benötigt zusätzliches WiFi-Modul)

## Unterschiede zu ESP8266/ESP32

- **MicroPython statt Arduino C++**
- **16-bit PWM** (0-65535) statt 8-bit oder 10-bit
- **Andere GPIO-Nummerierung** (GPIO 16, nicht PIN 16)
- **Thonny IDE** statt Arduino IDE
- **Automatischer Start** mit `main.py`

## Nützliche Links

- [MicroPython Dokumentation](https://docs.micropython.org/)
- [Raspberry Pi Pico W Pinout](https://datasheets.raspberrypi.com/picow/pico-w-datasheet.pdf)
- [Thonny IDE](https://thonny.org/)
- [MicroPython Downloads](https://micropython.org/download/)

