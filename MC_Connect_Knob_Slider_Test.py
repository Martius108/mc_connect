"""
MC_Connect - Knob und Slider Widget Test für Raspberry Pi Pico W

Dieses Skript testet die Knob- und Slider-Widgets mit einer LED an PIN 16.

Hardware:
- Raspberry Pi Pico W
- LED mit Vorwiderstand (220Ω - 1kΩ) an PIN 16

Funktionen:
- Empfängt MQTT-Commands von der MC_Connect App
- Steuert LED-Helligkeit über PWM (0-1024)
- Sendet Telemetry-Feedback zurück an die App
- Sendet Acknowledgment-Nachrichten

MQTT Topics:
- Empfängt: device/{deviceId}/command
- Sendet: device/{deviceId}/telemetry/{keyword}
- Sendet: device/{deviceId}/ack
- Sendet: device/{deviceId}/status

Benötigte Bibliotheken:
- umqtt.simple (sollte bereits in MicroPython enthalten sein)
- ujson (sollte bereits in MicroPython enthalten sein)
"""

import network
import time
import ujson
from machine import Pin, PWM
from umqtt.simple import MQTTClient

# ============================================
# KONFIGURATION - BITTE ANPASSEN
# ============================================

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

# ============================================
# GLOBALE VARIABLEN
# ============================================

wlan = None
mqtt_client = None
led_pwm = None
current_pwm_value = 0  # Aktueller PWM-Wert (0-1024)

# MQTT Topics
COMMAND_TOPIC = f"device/{DEVICE_ID}/command"
TELEMETRY_TOPIC = f"device/{DEVICE_ID}/telemetry/{LED_KEYWORD}"
ACK_TOPIC = f"device/{DEVICE_ID}/ack"
STATUS_TOPIC = f"device/{DEVICE_ID}/status"

# ============================================
# WIFI SETUP
# ============================================

def setup_wifi():
    """Stellt WiFi-Verbindung her"""
    global wlan
    
    print("\n" + "="*40)
    print("MC_Connect - Knob/Slider Test")
    print("Raspberry Pi Pico W")
    print("="*40 + "\n")
    
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)
    
    print(f"Verbinde mit WiFi: {WIFI_SSID}")
    wlan.connect(WIFI_SSID, WIFI_PASSWORD)
    
    # Warte auf Verbindung (max. 20 Sekunden)
    max_wait = 20
    while max_wait > 0:
        if wlan.status() < 0 or wlan.status() >= 3:
            break
        max_wait -= 1
        print(".", end="")
        time.sleep(1)
    
    if wlan.status() != 3:
        print("\n❌ WiFi-Verbindung fehlgeschlagen!")
        print("Bitte SSID und Passwort überprüfen.")
        raise RuntimeError("WiFi-Verbindung fehlgeschlagen")
    else:
        print("\n✅ WiFi verbunden!")
        print(f"IP-Adresse: {wlan.ifconfig()[0]}")

# ============================================
# MQTT CALLBACK - Verarbeitet eingehende Commands
# ============================================

def mqtt_callback(topic, payload):
    """Handler für eingehende MQTT-Nachrichten"""
    global current_pwm_value
    
    try:
        # Payload dekodieren
        message = payload.decode('utf-8')
        
        print(f"\n📥 Command empfangen:")
        print(f"Topic: {topic.decode('utf-8')}")
        print(f"Payload: {message}")
        
        # JSON parsen
        cmd = ujson.loads(message)
        
        # Command-Typ prüfen
        cmd_type = cmd.get("type", "")
        
        if cmd_type == "gpio":
            handle_gpio_command(cmd)
        else:
            print(f"⚠️ Unbekannter Command-Typ: {cmd_type}")
            send_ack_error(f"Unbekannter Command-Typ: {cmd_type}")
            
    except ValueError as e:
        print(f"❌ JSON Parse Fehler: {e}")
        send_ack_error(f"JSON Parse Fehler: {str(e)}")
    except Exception as e:
        print(f"❌ Fehler beim Verarbeiten des Commands: {e}")
        send_ack_error(f"Fehler: {str(e)}")

# ============================================
# GPIO COMMAND HANDLER
# ============================================

def handle_gpio_command(cmd):
    """Verarbeitet GPIO-Commands"""
    global current_pwm_value, led_pwm
    
    pin = cmd.get("pin", -1)
    value = cmd.get("value", -1)
    mode = cmd.get("mode", "output")
    
    print(f"\n🔧 GPIO Command:")
    print(f"  PIN: {pin}")
    print(f"  Wert: {value}")
    print(f"  Modus: {mode}")
    
    # Prüfe ob es unser LED-PIN ist
    if pin != LED_PIN:
        print(f"⚠️ Ignoriere Command für PIN {pin} (nicht konfiguriert)")
        send_ack_error(f"PIN {pin} nicht konfiguriert")
        return
    
    # Prüfe Wertbereich (0-1024 für PWM)
    if value < 0 or value > 1024:
        print(f"❌ Ungültiger Wert: {value} (muss 0-1024 sein)")
        send_ack_error(f"Ungültiger Wert: {value} (muss 0-1024 sein)")
        return
    
    # Setze PWM-Wert
    # Pico W PWM unterstützt 0-65535, aber wir verwenden 0-1024 für Kompatibilität
    # Skaliere 0-1024 auf 0-65535 für volle PWM-Auflösung
    pwm_duty = int((value / 1024) * 65535)
    led_pwm.duty_u16(pwm_duty)
    current_pwm_value = value
    
    print(f"✅ LED auf PIN {LED_PIN} gesetzt: PWM = {value} (duty = {pwm_duty})")
    
    # Sende sofort Telemetry-Feedback (wichtig für Widgets!)
    send_telemetry(value)
    
    # Sende Acknowledgment
    send_ack_success(pin, value)

# ============================================
# TELEMETRY SENDEN
# ============================================

def send_telemetry(value):
    """Sendet Telemetry-Daten an die App"""
    try:
        payload = ujson.dumps({
            "value": value,
            "unit": ""
        })
        
        mqtt_client.publish(TELEMETRY_TOPIC.encode(), payload.encode())
        print(f"📤 Telemetry gesendet: {TELEMETRY_TOPIC} = {value}")
    except Exception as e:
        print(f"❌ Fehler beim Senden der Telemetry: {e}")

# ============================================
# ACKNOWLEDGMENT SENDEN
# ============================================

def send_ack_success(pin, value):
    """Sendet Erfolgs-Acknowledgment"""
    try:
        payload = ujson.dumps({
            "status": "success",
            "data": {
                "pin": pin,
                "value": value
            }
        })
        
        mqtt_client.publish(ACK_TOPIC.encode(), payload.encode())
        print("✅ ACK gesendet: success")
    except Exception as e:
        print(f"❌ Fehler beim Senden des ACK: {e}")

def send_ack_error(error_message):
    """Sendet Fehler-Acknowledgment"""
    try:
        payload = ujson.dumps({
            "status": "error",
            "error": error_message
        })
        
        mqtt_client.publish(ACK_TOPIC.encode(), payload.encode())
        print(f"❌ ACK gesendet: error - {error_message}")
    except Exception as e:
        print(f"❌ Fehler beim Senden des ACK: {e}")

# ============================================
# STATUS SENDEN
# ============================================

def send_status(status):
    """Sendet Status-Nachricht"""
    try:
        mqtt_client.publish(STATUS_TOPIC.encode(), status.encode())
        print(f"📡 Status gesendet: {status}")
    except Exception as e:
        print(f"❌ Fehler beim Senden des Status: {e}")

# ============================================
# MQTT VERBINDUNG
# ============================================

def connect_mqtt():
    """Stellt MQTT-Verbindung her"""
    global mqtt_client
    
    client_id = f"MC_Connect_{DEVICE_ID}_{time.ticks_ms()}"
    
    mqtt_client = MQTTClient(
        client_id.encode(),
        MQTT_BROKER,
        MQTT_PORT,
        MQTT_USERNAME.encode() if MQTT_USERNAME else None,
        MQTT_PASSWORD.encode() if MQTT_PASSWORD else None,
        keepalive=60
    )
    
    mqtt_client.set_callback(mqtt_callback)
    
    while True:
        try:
            print("Verbinde mit MQTT Broker...", end="")
            mqtt_client.connect()
            print(" verbunden!")
            
            # Command Topic abonnieren
            mqtt_client.subscribe(COMMAND_TOPIC.encode())
            print(f"Abonniert: {COMMAND_TOPIC}")
            
            # Status senden
            send_status("online")
            
            return
            
        except Exception as e:
            print(f" fehlgeschlagen: {e}")
            print("Versuche es in 5 Sekunden erneut...")
            time.sleep(5)

# ============================================
# HAUPTPROGRAMM
# ============================================

def main():
    """Hauptprogramm"""
    global led_pwm, current_pwm_value
    
    # LED initialisieren
    led_pwm = PWM(Pin(LED_PIN))
    led_pwm.freq(1000)  # 1 kHz PWM-Frequenz
    led_pwm.duty_u16(0)  # LED initial aus
    current_pwm_value = 0
    
    print(f"LED initialisiert an PIN {LED_PIN}")
    
    # WiFi verbinden
    setup_wifi()
    
    # MQTT verbinden
    connect_mqtt()
    
    # Initialen Status senden
    send_status("online")
    send_telemetry(current_pwm_value)
    
    print("\n✅ Setup abgeschlossen!")
    print("Bereit für Commands...\n")
    
    # Hauptschleife
    try:
        while True:
            # MQTT-Nachrichten verarbeiten
            mqtt_client.check_msg()
            time.sleep(0.1)  # Kurze Pause für Stabilität
            
    except KeyboardInterrupt:
        print("\n\nProgramm beendet durch Benutzer")
    except Exception as e:
        print(f"\n\n❌ Fehler in Hauptschleife: {e}")
        raise
    finally:
        # Aufräumen
        if mqtt_client:
            try:
                mqtt_client.disconnect()
            except:
                pass
        if led_pwm:
            led_pwm.duty_u16(0)  # LED ausschalten
        print("Aufräumen abgeschlossen")

# ============================================
# PROGRAMM START
# ============================================

if __name__ == "__main__":
    main()

