"""One-shot MQTT broker diagnostic (no retained messages or commands)."""

import secrets
import socket
import ssl
import sys
from threading import Event

import paho.mqtt.client as mqtt

from agent import load_config


def main():
    try:
        host, port, username, password, device_id = load_config()
    except ValueError as exc:
        print(f"CONFIG ERROR: {exc}\nFix with .\\configure.ps1.", file=sys.stderr)
        return 1

    print(f"Checking broker {host}:{port} (TLS) for device {device_id}...", flush=True)
    try:
        socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except socket.gaierror as exc:
        print(f"DNS FAILED: {host} does not resolve ({exc}). Use your provider's real hostname.", file=sys.stderr)
        return 1
    print("DNS OK", flush=True)

    try:
        with socket.create_connection((host, port), timeout=5) as connection:
            connection.settimeout(5)
            with ssl.create_default_context().wrap_socket(connection, server_hostname=host):
                pass
    except (TimeoutError, ConnectionRefusedError, OSError) as exc:
        if isinstance(exc, ssl.SSLError):
            print(f"TLS FAILED: {exc}. Check the TLS port and certificate/hostname.", file=sys.stderr)
        else:
            print(f"TCP/TLS FAILED: {exc}. Check port, firewall, and provider endpoint.", file=sys.stderr)
        return 1
    print("TCP + TLS certificate/hostname verification OK", flush=True)

    client = mqtt.Client(
        callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
        client_id=f"ra-check-{device_id}-{secrets.token_hex(4)}",
        protocol=mqtt.MQTTv311,
        clean_session=True,
    )
    client.username_pw_set(username, password)
    client.tls_set_context(ssl.create_default_context())
    completed = Event()
    outcome = {"error": "Timed out waiting for broker MQTT response."}

    def on_connect(client, userdata, flags, reason_code, properties):
        if reason_code != 0:
            outcome["error"] = f"MQTT LOGIN REJECTED: {reason_code}. Verify the broker username/password."
            completed.set()
            return
        result, _ = client.subscribe(f"ra/{device_id}/request", qos=0)
        if result != mqtt.MQTT_ERR_SUCCESS:
            outcome["error"] = f"SUBSCRIBE FAILED: {result}. Check device ACLs."
            completed.set()

    def on_subscribe(client, userdata, mid, reason_codes, properties):
        if any(getattr(code, "is_failure", False) for code in reason_codes):
            outcome["error"] = "TOPIC ACCESS DENIED: Broker rejected subscription to request topic."
        else:
            outcome["error"] = None
        completed.set()

    def on_disconnect(client, userdata, disconnect_flags, reason_code, properties):
        if not completed.is_set():
            outcome["error"] = f"MQTT DISCONNECTED during check: {reason_code}"
            completed.set()

    client.on_connect = on_connect
    client.on_subscribe = on_subscribe
    client.on_disconnect = on_disconnect
    old_timeout = socket.getdefaulttimeout()
    try:
        socket.setdefaulttimeout(5)
        client.connect(host, port, keepalive=15)
    except (OSError, ValueError, ssl.SSLError) as exc:
        print(f"MQTT CONNECTION FAILED: {exc}", file=sys.stderr)
        return 1
    finally:
        socket.setdefaulttimeout(old_timeout)

    try:
        client.loop_start()
        completed.wait(8)
    finally:
        client.disconnect()
        client.loop_stop()

    if outcome["error"]:
        print(outcome["error"], file=sys.stderr)
        return 1
    print(f"MQTT login + subscribe to ra/{device_id}/request OK")
    print("BROKER CHECK PASSED. Agent may now be started using .\\run.ps1.")
    print("Note: Agent publish permission and phone-to-PC round trip are not yet tested.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
