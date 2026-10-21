"""Remote Accessor Phase 1: respond to MQTT CPU usage requests."""

import ipaddress
import json
import os
import re
import ssl
import sys
from datetime import datetime, timezone

import paho.mqtt.client as mqtt
import psutil


def load_config():
    host = os.getenv("RA_MQTT_HOST", "").strip()
    username = os.getenv("RA_MQTT_USERNAME", "").strip()
    password = os.getenv("RA_MQTT_PASSWORD", "")
    device_id = os.getenv("RA_DEVICE_ID", "").strip()
    port_text = os.getenv("RA_MQTT_PORT", "8883")

    if not host or not username or not password:
        raise ValueError("RA_MQTT_HOST, RA_MQTT_USERNAME and RA_MQTT_PASSWORD are required")
    if host.isdecimal() or "://" in host or "/" in host or any(c.isspace() for c in host):
        raise ValueError("RA_MQTT_HOST must be a real broker hostname or IP, not a number/URL. Run .\\configure.ps1")
    try:
        ipaddress.ip_address(host)
    except ValueError:
        labels = host.split(".")
        if (len(host) > 253 or
            not all(re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label) for label in labels) or
            host.lower().endswith((".example.com", ".example.net", ".example.org")) or
            host.lower().startswith("your-")):
            raise ValueError("RA_MQTT_HOST is not a usable broker hostname. Copy it from your broker dashboard")
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", device_id):
        raise ValueError("RA_DEVICE_ID must be 1-64 letters, digits, hyphens or underscores")
    try:
        port = int(port_text)
    except ValueError as exc:
        raise ValueError("RA_MQTT_PORT must be an integer") from exc
    if not 1 <= port <= 65535:
        raise ValueError("RA_MQTT_PORT must be between 1 and 65535")
    return host, port, username, password, device_id


def cpu_response(device_id):
    return json.dumps(
        {
            "device_id": device_id,
            "cpu_percent": psutil.cpu_percent(interval=0.1),
            "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        },
        separators=(",", ":"),
    )


def handle_message(client, message, device_id):
    request_topic = f"ra/{device_id}/request"
    if message.topic != request_topic or message.retain or message.payload != b"get_cpu":
        return
    client.publish(f"ra/{device_id}/response", cpu_response(device_id), qos=0, retain=False)


def main():
    try:
        host, port, username, password, device_id = load_config()
    except ValueError as exc:
        raise SystemExit(f"Configuration error: {exc}") from exc

    client = mqtt.Client(
        callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
        client_id=f"ra-{device_id}",
        protocol=mqtt.MQTTv311,
        clean_session=True,
    )
    client.username_pw_set(username, password)
    client.tls_set_context(ssl.create_default_context())  # Validates broker certificate and hostname.
    client.reconnect_delay_set(min_delay=1, max_delay=60)

    def on_connect(client, userdata, flags, reason_code, properties):
        if reason_code != 0:
            print(f"MQTT connection refused: {reason_code}", file=sys.stderr)
            return
        result, _ = client.subscribe(f"ra/{device_id}/request", qos=0)
        if result != mqtt.MQTT_ERR_SUCCESS:
            print(f"MQTT subscribe failed: {result}", file=sys.stderr)
        else:
            print(f"Connected; listening on ra/{device_id}/request", flush=True)

    def on_subscribe(client, userdata, mid, reason_codes, properties):
        if any(code.is_failure for code in reason_codes):
            print("Broker rejected request-topic subscription (check ACLs)", file=sys.stderr)

    def on_connect_fail(client, userdata):
        print("Broker unreachable; retrying", file=sys.stderr)

    client.on_connect = on_connect
    client.on_subscribe = on_subscribe
    client.on_connect_fail = on_connect_fail
    client.on_message = lambda client, userdata, message: handle_message(client, message, device_id)
    client.connect_async(host, port, keepalive=60)
    try:
        client.loop_forever(retry_first_connection=True)
    except KeyboardInterrupt:
        pass
    finally:
        client.disconnect()


if __name__ == "__main__":
    main()
