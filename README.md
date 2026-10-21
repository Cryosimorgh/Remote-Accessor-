# Remote Accessor — Phase 1

Read a PC's CPU usage from a phone through an **existing MQTT broker**. Both devices connect outbound to the broker; no static IP, custom server, port forwarding, or phone app development is needed.

## 1. Prepare the broker

Use an existing MQTT broker with **TLS on port 8883** (or its TLS port), a certificate trusted by your PC, and username/password authentication. Create a unique device ID, e.g. `pc-01`. Use separate broker credentials for the PC agent and phone if the broker supports them.

Restrict broker-side topic ACLs (syntax varies by provider):

| Client | May subscribe (read) | May publish (write) |
| --- | --- | --- |
| PC agent | `ra/pc-01/request` | `ra/pc-01/response` |
| Phone | `ra/pc-01/response` | `ra/pc-01/request` |

Do not grant wildcard topic access unless needed. Use non-retained messages for requests. This demo uses QoS 0 and a clean session, so offline commands are dropped rather than replayed. The agent additionally ignores any request delivered with the MQTT retained flag set.

## 2. Install on the PC

Requires Python 3.9+.

**Windows PowerShell:**

~~~powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
$env:RA_MQTT_HOST = "your-broker.example.com"
$env:RA_MQTT_PORT = "8883"
$env:RA_MQTT_USERNAME = "your-agent-username"
$env:RA_MQTT_PASSWORD = "your-agent-password"
$env:RA_DEVICE_ID = "pc-01"
.\.venv\Scripts\python.exe agent.py
~~~

**Linux / macOS:**

~~~sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
export RA_MQTT_HOST='your-broker.example.com'
export RA_MQTT_PORT=8883
export RA_MQTT_USERNAME='your-agent-username'
export RA_MQTT_PASSWORD='your-agent-password'
export RA_DEVICE_ID='pc-01'
.venv/bin/python agent.py
~~~

See `.env.example` for all settings. It is a **reference only**: there is no `.env` parser, so set variables in your shell or OS. `RA_MQTT_PORT` defaults to `8883`. Keep credentials out of source control. The agent verifies the broker's TLS certificate and hostname; it does not have an insecure-TLS switch. Stop with Ctrl+C.

## 3. Request CPU usage from the phone

In any existing phone MQTT client that supports TLS and username/password authentication:

1. Connect to the **same broker** using the broker hostname, TLS port, and your phone client's credentials. Enable TLS certificate verification.
2. **Subscribe** to `ra/pc-01/response` (replace `pc-01` with your device ID).
3. **Publish** the exact UTF-8 text `get_cpu` to `ra/pc-01/request`, **QoS 0**, **retain OFF**.
4. Read the response on `ra/pc-01/response`:

~~~json
{"device_id":"pc-01","cpu_percent":12.5,"timestamp":"2026-10-21T10:30:00Z"}
~~~

The value and UTC timestamp above are illustrative. One message yields one CPU measurement (0.1-second sampling interval); there is no polling until you request it again. To test reconnection, briefly disconnect/reconnect the PC's network, then issue a **new** request.

**If no reply:** Check agent's `Connected` output; compare device ID, broker/port, and topic spelling; check both clients' ACLs; ensure the phone subscribes *before* publishing; and ensure `retain` is off. When the agent is disconnected, requests are intentionally not queued.

## 4. Local test (no broker needed)

~~~powershell
.\.venv\Scripts\python.exe -m unittest -v test_agent.py
~~~

Or on Linux/macOS:

~~~sh
.venv/bin/python -m unittest -v test_agent.py
~~~

Tests cover config validation, the CPU response, and rejection of retained, unknown, or wrong-topic commands. This is a local protocol/handler test, **not** a live end-to-end broker test; that still requires your real broker credentials and both clients.

## Resource profile

- **Idle CPU:** estimated below 0.1% on a normal PC (no continuous sampling; MQTT socket loop waits for traffic).
- **RAM:** estimated 15–35 MiB for the Python agent process, depending on OS and Python build.
- **Network:** MQTT keepalive is 60 seconds (one PINGREQ and PINGRESP = **4 MQTT bytes per minute** while idle, plus TCP/TLS/IP overhead). Startup TLS handshake typically adds a few KB. Each CPU request/response exchange is roughly **100–200 MQTT bytes** for a short device ID, plus transport overhead; it happens only on request.
- **Latency:** each measurement waits ~100 ms for CPU sampling, plus broker and network latency.

These are estimates, not readings from your PC or broker. `paho-mqtt` manages reconnection with exponential backoff from 1 to 60 seconds. No daemon, database, telemetry timer, HTTP endpoint, or arbitrary command execution is present.
