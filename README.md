# Remote Accessor — Phase 1

Ask a PC for its current CPU percentage from a phone through an **existing hosted MQTT broker**. No static IP, port forwarding, custom server, or mobile app.

## Windows PowerShell — do this first

First test CPU monitoring **without the internet or broker credentials**:

~~~powershell
git pull
.\setup.ps1      # Installs Python dependencies ONLY
.\test.ps1       # OFFLINE tests + actual CPU reading
~~~

Successful output includes `"cpu_percent"` and `"timestamp"` and then `Local test passed`. This does **not** test remote access.

If script execution is blocked, run `Set-ExecutionPolicy -Scope Process Bypass` in that PowerShell session, then retry.

### Remote connection — only after offline test

You must have a **real hosted MQTT broker account**. The broker is not your PC or an IP address you invent. In your broker provider's dashboard, find its **TLS hostname**, **TLS port**, and **username/password**. An example of the hostname *format* is `cluster-name.s1.eu.hivemq.cloud` (not a working address). Do **not** enter `2` or any placeholder. The usual TLS port is `8883`, but use the exact port supplied by your provider.

~~~powershell
.\configure.ps1  # Enter actual broker details; overwrites prior config
.\check.ps1      # ONE check: DNS -> TCP/TLS -> MQTT auth -> subscription
.\run.ps1        # Starts agent only when initial broker check succeeds
~~~

The Windows configuration is stored in `.env.windows.json` (ignored by Git); the password is encrypted with Windows DPAPI for your Windows user. Previous incorrect settings? **Just run `.\configure.ps1` again.** There is no need to reinstall dependencies.

| Diagnostic | What to check |
| --- | --- |
| `CONFIG ERROR` | Reconfigure using real broker details |
| `DNS FAILED` | Broker hostname from dashboard |
| `TCP/TLS FAILED` | Broker TLS port, firewall, certificate |
| `MQTT LOGIN REJECTED` | Broker username/password |
| `TOPIC ACCESS DENIED` | Broker topic ACLs |
| `BROKER CHECK PASSED` | PC can connect and subscribe; launch agent |

The broker check verifies connection and subscription, **not** publish permissions or a full phone-to-PC round trip. Agent retries automatically after later network interruptions.

## Real phone test

When the PC says `Connected; listening on ra/pc-01/request`, use an existing MQTT client on your phone with TLS enabled, connected to the **same broker**. Use your phone's own broker credentials if possible.

1. Subscribe to `ra/<device_id>/response` **first**.
2. Publish exact UTF-8 text `get_cpu` on `ra/<device_id>/request`, QoS 0, retained **OFF**.
3. Read a response like this (example values):

~~~json
{"device_id":"pc-01","cpu_percent":12.5,"timestamp":"2026-10-21T10:30:00Z"}
~~~

Replace `<device_id>` with the exact ID entered during configuration. Each request triggers a 0.1-second CPU sample. Stop the PC agent with Ctrl+C.

### Broker ACLs

| Client | May subscribe | May publish |
| --- | --- | --- |
| PC agent | `ra/pc-01/request` | `ra/pc-01/response` |
| Phone | `ra/pc-01/response` | `ra/pc-01/request` |

Substitute your device ID. Use broker authentication and verified TLS. Do not retain command messages. The agent rejects retained requests and ignores anything other than `get_cpu`.

## Linux/macOS (Bash)

Existing Bash helper: `bash setup.sh` installs and configures, `bash setup.sh test` runs tests, `bash setup.sh run` starts the agent. This older Linux/macOS helper still combines setup and broker configuration; the **native Windows commands above are separated**.

## Resource estimates

Python 3.9+; dependencies: `paho-mqtt`, `psutil`. Expected approximately **15–35 MiB RAM**, **below 0.1% idle CPU**, MQTT PINGREQ/PINGRESP ~**4 bytes/minute** plus TCP/IP/TLS overhead, and **100–200 MQTT bytes** per request/response plus overhead. These are estimates, not measurements of your machine or broker. No background polling, database, GUI, arbitrary commands, or ESP8266 support.
