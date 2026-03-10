# lms-dab-radio

DAB+ radio reception via RTL-SDR for Lyrion Music Server (LMS).

Uses `welle-cli` to receive and decode a full DAB multiplex, and streams each service permanently to Icecast via ffmpeg. An LMS plugin displays all services grouped by MUX with live metadata (current song, genre).

---

## Architecture

```
RTL-SDR dongle
      ↓
  welle-cli -c 11C -Dw 9090   (decodes all services, serves MP3 over HTTP)
      ↓ http://localhost:9090/mp3/<SID>   (one per audio service)
  ffmpeg → Icecast /dab/dr-p1
  ffmpeg → Icecast /dab/dr-p2
  ffmpeg → Icecast /dab/dr-p3
  ...one ffmpeg per service...
      ↑
  dab-daemon  (HTTP API — service discovery, MUX switching, DLS metadata)
      ↑
  LMS Plugin  (Radio menu, grouped by MUX, live stream URLs)
```

**Service discovery:** welle-cli scans the MUX automatically. No manual SID configuration needed — services are discovered at startup and cached.

**Live metadata:** the daemon polls welle-cli every 10 seconds for DLS (Dynamic Label Service) updates and pushes current song, genre, and description to Icecast.

**No startup latency for listeners:** all services stream to Icecast permanently. Selecting a station in LMS just connects to its Icecast mount — instant playback.

---

## Prerequisites

- Linux server (Debian/Ubuntu recommended)
- RTL-SDR USB dongle connected and working
- `welle-cli` built from [welle.io](https://github.com/AlbrechtL/welle.io):
  ```bash
  sudo apt install cmake librtlsdr-dev libfftw3-dev libfaad-dev libmpg123-dev libmp3lame-dev
  git clone https://github.com/AlbrechtL/welle.io
  cd welle.io && mkdir build && cd build
  cmake -DBUILD_WELLE_CLI=ON -DBUILD_GUI_APP=OFF ..
  make -j$(nproc)
  sudo cp src/welle-cli/welle-cli /usr/local/bin/
  ```
- `ffmpeg` installed: `sudo apt install ffmpeg`
- Icecast2 running (local install or Docker)
- Lyrion Music Server 8.x or 9.x

### Verify reception

Before configuring the daemon, confirm welle-cli can receive your MUX:

```bash
welle-cli -c 11C -s any 2>&1 | head -20
# Should show: "Wait for service list" followed by TII data
```

---

## Finding your DAB channel

You only need the channel name (e.g. `11C`), not frequencies or SIDs — welle-cli handles discovery automatically.

**Common Danish MUX channels:**
| MUX | Channel | Frequency |
|-----|---------|-----------|
| DR MUX | 11C | 220.352 MHz |
| Lokal DAB | 10B | 212.928 MHz |

For other countries, see the [ETSI DAB channel table](https://www.etsi.org/technologies/dab).

---

## Daemon Setup

### 1. Configure

Edit `daemon/dab-daemon.py` and fill in your values:

```python
WELLE_CLI_BIN      = "/usr/local/bin/welle-cli"
WELLE_PORT         = 9090          # internal port for welle-cli HTTP — not exposed

ICECAST_HOST       = "your-icecast-host"
ICECAST_PORT       = 8000
ICECAST_SOURCE     = "your-source-password"
ICECAST_ADMIN_USER = "admin"
ICECAST_ADMIN_PASS = "your-admin-password"  # used as fallback for metadata auth

DAEMON_PORT        = 9980
```

Define your MUX list — one entry per DAB multiplex you want to receive:

```python
MUX_LIST = [
    {
        "key":     "mux1",
        "name":    "DR MUX (11C)",
        "channel": "11C",
    },
    # { "key": "mux2", "name": "Lokal DAB (10B)", "channel": "10B" },
]
```

Optionally configure where to store the service cache:

```python
SERVICES_CACHE = "/var/lib/dab-daemon/services.json"
```

```bash
sudo mkdir -p /var/lib/dab-daemon
sudo chown $USER /var/lib/dab-daemon
```

### 2. Install

```bash
sudo cp daemon/dab-daemon.py /usr/local/bin/dab-daemon.py
sudo chmod +x /usr/local/bin/dab-daemon.py
```

### 3. Install as a systemd service

```bash
sudo cp daemon/dab-daemon.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable dab-daemon
sudo systemctl start dab-daemon
```

Check status and logs:
```bash
sudo systemctl status dab-daemon
journalctl -u dab-daemon -f
```

### 4. Test the API

```bash
# Current status and active streams
curl http://localhost:9980/status

# List discovered MUXes and services
curl http://localhost:9980/muxes

# Force rescan of current MUX
curl http://localhost:9980/rescan

# Switch to a different MUX
curl http://localhost:9980/switch/mux2

# Stop everything
curl -X POST http://localhost:9980/stop
```

### API reference

| Method | Path | Description |
|--------|------|-------------|
| GET | `/status` | Current MUX, welle-cli state, and all active stream URLs |
| GET | `/muxes` | List all MUXes with discovered services and Icecast stream URLs |
| GET | `/switch/<key>` | Switch to MUX by key (async, ~15-30 s for discovery) |
| POST | `/switch?mux=<key>` | Switch to MUX by key |
| GET | `/rescan` | Force rescan of current MUX (clears cache) |
| POST | `/stop` | Stop all ffmpeg pipelines and welle-cli |

---

## LMS Plugin Installation

### Manual install

Copy `LMSPlugin/DABRadio` to your LMS plugin directory:
- Docker: `/config/cache/Plugins/DABRadio`
- Standard: `/usr/share/squeezeboxserver/Plugins/DABRadio`

Restart LMS.

### Plugin configuration

Go to **Settings → Plugins → DAB Radio → Settings**:

- **Daemon URL** — e.g. `http://192.168.1.50:9980`
- **Icecast Host** — hostname or IP of your Icecast server
- **Icecast Port** — typically `8000`

The plugin appears under **Radio → DAB Radio** in LMS. Services are grouped by MUX. Selecting a service connects directly to its permanent Icecast stream.

---

## MUX Switching

When you switch MUX via the API, the daemon:
1. Stops all ffmpeg pipelines
2. Restarts welle-cli on the new channel
3. Waits up to 30 seconds for service discovery
4. Starts new ffmpeg pipelines for all discovered audio services

The LMS plugin always queries `/muxes` for the current service list, so after a switch the station list updates on next browse.

---

## Metadata

The daemon pushes three types of metadata to each Icecast mount:

| Field | Source | Example |
|-------|--------|---------|
| Stream name | Service label from DAB | `DR P1` |
| Genre | DAB Programme Type (PTY) | `Talk`, `Pop Music`, `Jazz and Blues` |
| Current song | DLS (Dynamic Label Service) | `Now on air: P1 Morgen` |

DLS is polled every 10 seconds and pushed to Icecast using the source password. The admin password is used as a fallback if the source password is rejected.

> **Note:** Icecast 2.4 expects metadata URL-encoded as Latin-1. The daemon handles this automatically.

---

## License

MIT
