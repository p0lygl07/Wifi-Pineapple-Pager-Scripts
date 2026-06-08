#!/bin/bash
# ============================================
# Network Security Audit Script
# Author: p0lygl07
# Purpose: Authorized network security auditing
# ONLY USE ON NETWORKS YOU OWN OR HAVE
# EXPLICIT WRITTEN PERMISSION TO TEST
# ============================================

# ============================================
# CONFIGURATION
# ============================================
INTERFACE="wlan0"
MONITOR_IFACE="wlan0mon"
OUTPUT_DIR="/tmp/audit_$(date +%Y%m%d_%H%M%S)"
LOGFILE="$OUTPUT_DIR/audit.log"
ALERT_FILE="$OUTPUT_DIR/alerts.log"
REPORT_FILE="$OUTPUT_DIR/report.txt"

# Alert thresholds
MAX_OPEN_PORTS=10
WEAK_ENCRYPTION=("WEP" "OPEN" "NONE")

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# LOGGING & ALERTS
# ============================================
log() {
    echo -e "[$(date '+%H:%M:%S')] $1" | tee -a $LOGFILE
}

alert() {
    local severity=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $severity in
        CRITICAL)
            echo -e "${RED}[CRITICAL ALERT] $message${NC}" | tee -a $ALERT_FILE
            ;;
        HIGH)
            echo -e "${RED}[HIGH] $message${NC}" | tee -a $ALERT_FILE
            ;;
        MEDIUM)
            echo -e "${YELLOW}[MEDIUM] $message${NC}" | tee -a $ALERT_FILE
            ;;
        LOW)
            echo -e "${BLUE}[LOW] $message${NC}" | tee -a $ALERT_FILE
            ;;
        INFO)
            echo -e "${GREEN}[INFO] $message${NC}" | tee -a $ALERT_FILE
            ;;
    esac
    
    echo "[$timestamp] [$severity] $message" >> $ALERT_FILE
}

# ============================================
# DEPENDENCY CHECK
# ============================================
check_deps() {
    log "Checking dependencies..."
    local deps=("nmap" "aircrack-ng" "airodump-ng" "airmon-ng" "iwconfig" "arp-scan")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v $dep &>/dev/null; then
            missing+=($dep)
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        alert HIGH "Missing dependencies: ${missing[*]}"
        echo "Install with: apt install ${missing[*]}"
        exit 1
    fi
    
    log "${GREEN}All dependencies found${NC}"
}

# ============================================
# SETUP
# ============================================
setup() {
    log "Setting up audit environment..."
    mkdir -p $OUTPUT_DIR
    
    # Check root
    if [ "$EUID" -ne 0 ]; then
        alert CRITICAL "Must run as root"
        exit 1
    fi
    
    # Enable monitor mode
    log "Enabling monitor mode on $INTERFACE..."
    airmon-ng check kill &>/dev/null
    airmon-ng start $INTERFACE &>/dev/null
    
    if iwconfig $MONITOR_IFACE &>/dev/null; then
        alert INFO "Monitor mode enabled on $MONITOR_IFACE"
    else
        alert HIGH "Failed to enable monitor mode"
        exit 1
    fi
}

# ============================================
# WIRELESS SCAN
# ============================================
wireless_scan() {
    log "Starting wireless network scan (60 seconds)..."
    
    airodump-ng $MONITOR_IFACE \
        --output-format csv \
        --write $OUTPUT_DIR/wireless \
        2>/dev/null &
    
    SCAN_PID=$!
    
    # Progress indicator
    for i in $(seq 1 60); do
        echo -ne "\r[*] Scanning... ${i}/60s"
        sleep 1
    done
    echo ""
    
    kill $SCAN_PID 2>/dev/null
    wait $SCAN_PID 2>/dev/null
    
    # Parse results
    if [ -f "$OUTPUT_DIR/wireless-01.csv" ]; then
        analyze_wireless
    else
        alert MEDIUM "No wireless scan results found"
    fi
}

# ============================================
# ANALYZE WIRELESS RESULTS
# ============================================
analyze_wireless() {
    log "Analyzing wireless networks..."
    
    local networks=0
    local weak_enc=0
    local hidden=0
    
    while IFS=',' read -r bssid first_seen last_seen channel speed privacy cipher auth power beacons iv lan_ip id_len essid key; do
        # Skip header lines
        [[ "$bssid" == *"BSSID"* ]] && continue
        [[ "$bssid" == *"Station"* ]] && break
        [[ -z "$bssid" ]] && continue
        
        bssid=$(echo $bssid | tr -d ' ')
        essid=$(echo $essid | tr -d ' ')
        privacy=$(echo $privacy | tr -d ' ')
        power=$(echo $power | tr -d ' ')
        
        ((networks++))
        
        # Check for weak encryption
        for weak in "${WEAK_ENCRYPTION[@]}"; do
            if [[ "$privacy" == *"$weak"* ]]; then
                alert HIGH "Weak encryption detected: SSID=$essid BSSID=$bssid Encryption=$privacy"
                ((weak_enc++))
            fi
        done
        
        # Check for hidden networks
        if [ -z "$essid" ] || [ "$essid" == "\\x00" ]; then
            alert MEDIUM "Hidden network detected: BSSID=$bssid Channel=$channel"
            ((hidden++))
        fi
        
        # Check signal strength for rogue AP detection
        if [ ! -z "$power" ] && [ "$power" -gt -50 ] 2>/dev/null; then
            alert MEDIUM "Strong signal AP nearby (possible rogue): SSID=$essid Power=${power}dBm"
        fi
        
    done < "$OUTPUT_DIR/wireless-01.csv"
    
    alert INFO "Wireless scan complete: $networks networks found, $weak_enc weak encryption, $hidden hidden"
}

# ============================================
# HOST DISCOVERY
# ============================================
discover_hosts() {
    local subnet=$1
    log "Discovering hosts on $subnet..."
    
    # ARP scan for live hosts
    arp-scan --interface=$INTERFACE $subnet 2>/dev/null | \
        grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" > $OUTPUT_DIR/hosts.txt
    
    local count=$(wc -l < $OUTPUT_DIR/hosts.txt)
    alert INFO "Discovered $count live hosts on $subnet"
    
    cat $OUTPUT_DIR/hosts.txt | tee -a $LOGFILE
}

# ============================================
# PORT SCAN & SERVICE DETECTION
# ============================================
port_scan() {
    local target=$1
    log "Port scanning $target..."
    
    # Fast scan with service detection
    nmap -sV -sC -T4 \
        --open \
        -oN $OUTPUT_DIR/portscan_$(echo $target | tr '.' '_').txt \
        $target 2>/dev/null
    
    # Parse results for alerts
    analyze_ports $target
}

analyze_ports() {
    local target=$1
    local scanfile="$OUTPUT_DIR/portscan_$(echo $target | tr '.' '_').txt"
    
    [ ! -f "$scanfile" ] && return
    
    # Count open ports
    local open_ports=$(grep -c "^[0-9].*open" $scanfile 2>/dev/null || echo 0)
    
    if [ "$open_ports" -gt "$MAX_OPEN_PORTS" ]; then
        alert HIGH "$target has $open_ports open ports (threshold: $MAX_OPEN_PORTS)"
    fi
    
    # Check for dangerous services
    local dangerous_services=("telnet" "ftp" "rsh" "rlogin" "finger" "tftp")
    for svc in "${dangerous_services[@]}"; do
        if grep -qi "$svc" $scanfile; then
            alert HIGH "Dangerous service detected on $target: $svc"
        fi
    done
    
    # Check for default credentials hint
    if grep -qi "default" $scanfile; then
        alert MEDIUM "Possible default credentials on $target — verify manually"
    fi
    
    # Check for outdated services
    if grep -qiE "Apache/2\.[0-3]|nginx/1\.[0-9]\." $scanfile; then
        alert MEDIUM "Potentially outdated web server detected on $target"
    fi
    
    # Check for SMB
    if grep -qi "445/tcp.*open" $scanfile; then
        alert MEDIUM "SMB open on $target — check for EternalBlue/PrintNightmare"
    fi
    
    # Check for RDP
    if grep -qi "3389/tcp.*open" $scanfile; then
        alert MEDIUM "RDP open on $target — check for BlueKeep"
    fi
    
    # Check for database ports
    local db_ports=("3306" "5432" "1433" "27017" "6379")
    for port in "${db_ports[@]}"; do
        if grep -qi "${port}/tcp.*open" $scanfile; then
            alert HIGH "Database port $port open on $target — verify authentication required"
        fi
    done
}

# ============================================
# GENERATE REPORT
# ============================================
generate_report() {
    log "Generating audit report..."
    
    cat > $REPORT_FILE << EOF
============================================
NETWORK SECURITY AUDIT REPORT
============================================
Date:       $(date)
Auditor:    kuliex270
Interface:  $INTERFACE
Output Dir: $OUTPUT_DIR

============================================
ALERT SUMMARY
============================================
$(grep "\[CRITICAL\]" $ALERT_FILE | wc -l) CRITICAL alerts
$(grep "\[HIGH\]" $ALERT_FILE | wc -l) HIGH alerts
$(grep "\[MEDIUM\]" $ALERT_FILE | wc -l) MEDIUM alerts
$(grep "\[LOW\]" $ALERT_FILE | wc -l) LOW alerts

============================================
CRITICAL ALERTS
============================================
$(grep "\[CRITICAL\]" $ALERT_FILE)

============================================
HIGH ALERTS
============================================
$(grep "\[HIGH\]" $ALERT_FILE)

============================================
MEDIUM ALERTS
============================================
$(grep "\[MEDIUM\]" $ALERT_FILE)

============================================
RECOMMENDATIONS
============================================
1. Replace WEP/Open networks with WPA2/WPA3
2. Disable unnecessary services (Telnet, FTP)
3. Change default credentials immediately
4. Update all outdated software
5. Restrict database access to localhost only
6. Implement network segmentation

============================================
FILES GENERATED
============================================
$(ls -la $OUTPUT_DIR/)
============================================
EOF

    echo ""
    echo -e "${GREEN}Report saved to: $REPORT_FILE${NC}"
    cat $REPORT_FILE
}

# ============================================
# CLEANUP
# ============================================
cleanup() {
    log "Cleaning up..."
    airmon-ng stop $MONITOR_IFACE &>/dev/null
    service NetworkManager restart &>/dev/null
    log "Audit complete. Results in $OUTPUT_DIR"
}

# ============================================
# MAIN
# ============================================
banner() {
    echo -e "${GREEN}"
    echo "============================================"
    echo "   Network Security Audit Tool"
    echo "   Author: kuliex270"
    echo "   FOR AUTHORIZED USE ONLY"
    echo "============================================"
    echo -e "${NC}"
}

main() {
    banner
    check_deps
    setup
    
    case "$1" in
        wireless)
            wireless_scan
            ;;
        hosts)
            [ -z "$2" ] && { echo "Usage: $0 hosts <subnet>"; exit 1; }
            discover_hosts $2
            ;;
        portscan)
            [ -z "$2" ] && { echo "Usage: $0 portscan <target>"; exit 1; }
            port_scan $2
            ;;
        full)
            [ -z "$2" ] && { echo "Usage: $0 full <subnet>"; exit 1; }
            wireless_scan
            discover_hosts $2
            while IFS= read -r line; do
                ip=$(echo $line | awk '{print $1}')
                [ ! -z "$ip" ] && port_scan $ip
            done < $OUTPUT_DIR/hosts.txt
            ;;
        *)
            echo "Usage: $0 {wireless|hosts <subnet>|portscan <target>|full <subnet>}"
            echo ""
            echo "Examples:"
            echo "  $0 wireless                    # Scan wireless networks"
            echo "  $0 hosts 192.168.1.0/24        # Discover hosts"
            echo "  $0 portscan 192.168.1.1        # Port scan single host"
            echo "  $0 full 192.168.1.0/24         # Full audit"
            exit 1
            ;;
    esac
    
    generate_report
    cleanup
}

# Trap cleanup on exit
trap cleanup EXIT INT TERM

main "$@"