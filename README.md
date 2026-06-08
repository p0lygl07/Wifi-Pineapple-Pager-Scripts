# 🍍 WiFi Pineapple Security Scripts

> **AUTHORIZED USE ONLY** — These scripts are intended for legal penetration testing and security research on networks you own or have explicit written permission to test. Unauthorized use is illegal under the Computer Fraud and Abuse Act (CFAA) and equivalent laws globally.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Scripts](#scripts)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Features](#features)
- [Disclaimer](#disclaimer)

---

## Overview

A collection of WiFi Pineapple red team and network security audit scripts designed for authorized penetration testing engagements. Built for security researchers and bug bounty hunters.

**Author:** kuliex270 (p0lygl07)  
**Platform:** WiFi Pineapple / Kali Linux  
**Language:** Bash

---

## Scripts

| Script | Description | Use Case |
|--------|-------------|----------|
| `audit.sh` | Automated network security audit with alerts | Defensive / Security Assessment |
| `redteam.sh` | Full red team engagement automation | Offensive / Authorized Pentesting |

---

## Requirements

### Hardware
- WiFi Pineapple (any model)
- Wireless adapter supporting monitor mode and packet injection

### Software
```
aircrack-ng
airodump-ng
airmon-ng
aireplay-ng
nmap
arp-scan
hostapd
dnsmasq
tcpdump
iwconfig
```

### Install dependencies
```bash
apt update && apt install -y \
    aircrack-ng \
    nmap \
    arp-scan \
    hostapd \
    dnsmasq \
    tcpdump
```

---

## Installation

```bash
# Clone the repository
git clone https://github.com/p0lygl07/pineapple-scripts
cd pineapple-scripts

# Make scripts executable
chmod +x audit.sh redteam.sh

# Verify dependencies
sudo ./audit.sh
sudo ./redteam.sh
```

---

## Usage

### Network Security Audit (`audit.sh`)

```bash
# Wireless network scan only
sudo ./audit.sh wireless

# Discover live hosts on subnet
sudo ./audit.sh hosts 192.168.1.0/24

# Port scan single target
sudo ./audit.sh portscan 192.168.1.1

# Full audit — wireless + hosts + port scan
sudo ./audit.sh full 192.168.1.0/24
```

### Red Team Engagement (`redteam.sh`)

```bash
# Passive reconnaissance only
sudo ./redteam.sh recon

# Enumerate connected clients
sudo ./redteam.sh clients

# Capture WPA handshake
sudo ./redteam.sh handshake

# Deploy evil twin AP
sudo ./redteam.sh eviltwin

# Traffic capture and analysis
sudo ./redteam.sh traffic

# Full engagement — all phases
sudo ./redteam.sh full
```

---

## Features

### `audit.sh` — Network Security Audit

```
✅ Passive wireless scanning
✅ Weak encryption detection (WEP/OPEN)
✅ Hidden network detection
✅ Rogue AP detection by signal strength
✅ Live host discovery via ARP scan
✅ Port scanning with service detection
✅ Dangerous service alerts (Telnet, FTP, rsh)
✅ Exposed database port detection
✅ Outdated web server detection
✅ Open RDP/SMB vulnerability hints
✅ Severity-based alert system (CRITICAL/HIGH/MEDIUM/LOW)
✅ Automated report generation
```

### `redteam.sh` — Red Team Engagement

```
✅ Phase 1 — Passive wireless reconnaissance
✅ Phase 2 — Connected client enumeration
✅ Phase 3 — WPA handshake capture with deauth
✅ Phase 4 — Evil twin AP deployment
✅ Phase 5 — Traffic capture and analysis
✅ Cleartext credential detection
✅ DNS query logging
✅ Automated engagement report generation
✅ Full cleanup on exit
```

---

## Output Structure

```
/tmp/audit_YYYYMMDD_HHMMSS/
├── audit.log           # Full session log
├── alerts.log          # All alerts by severity
├── report.txt          # Final audit report
├── wireless-01.csv     # Raw wireless scan data
├── hosts.txt           # Discovered live hosts
└── portscan_*.txt      # Per-host port scan results

/tmp/engagement_YYYYMMDD_HHMMSS/
├── engagement.log      # Full engagement log
├── report.txt          # Final engagement report
├── recon/              # Reconnaissance data
├── clients/            # Client enumeration data
├── handshakes/         # Captured handshakes
├── eviltwin/           # Evil twin config and logs
└── traffic/            # Packet captures and analysis
```

---

## Alert Severity Levels

| Level | Description | Example |
|-------|-------------|---------|
| 🔴 CRITICAL | Immediate action required | Script not running as root |
| 🔴 HIGH | Serious security issue | WEP encryption, exposed DB port |
| 🟡 MEDIUM | Moderate risk | Hidden network, open RDP |
| 🔵 LOW | Informational risk | Minor configuration issue |
| 🟢 INFO | Status information | Scan complete, hosts found |

---

## Related Tools

- [WiFi Pineapple](https://hak5.org/products/wifi-pineapple) — Hardware platform
- [Aircrack-ng](https://www.aircrack-ng.org/) — Wireless security toolkit
- [Nmap](https://nmap.org/) — Network scanner
- [Burp Suite](https://portswigger.net/burp) — Web security testing

---

## Author

**Joshua Burton** (kuliex270)  
GitHub: [p0lygl07](https://github.com/p0lygl07)  
HackerOne: kuliex270  
SNHU — Cybersecurity

---

## Disclaimer

These tools are provided for **educational purposes** and **authorized security testing only**.

- Only use on networks you own or have **explicit written permission** to test
- Unauthorized interception of network traffic is illegal
- The author assumes no liability for misuse
- Always obtain proper authorization before conducting any security testing

**Relevant Laws:**
- Computer Fraud and Abuse Act (CFAA) — USA
- Computer Misuse Act — UK
- Cybercrime laws vary by jurisdiction — know your local laws

---

## License

MIT License — See [LICENSE](LICENSE) for details.

---

*Built for the security community — use responsibly* 🔐
