#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Delling Service Diagnostics
# Check service status and troubleshoot failures
# ═══════════════════════════════════════════════════════════════════════════

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Service arrays
ALL_SERVICES=(
    "delling-dashboard"
    "tinymedia"
    "kiwix"
    "rtl-fm-radio"
    "welle-cli"
    "openwebrx"
    "dump1090-fa"
    "aiscatcher"
)

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

check_service_status() {
    local service=$1
    
    # Check if service exists
    if ! systemctl list-unit-files | grep -q "^${service}.service"; then
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}SERVICE:${NC} $service"
        echo -e "${YELLOW}STATUS:${NC}  NOT INSTALLED"
        return
    fi
    
    # Get detailed status
    local active=$(systemctl is-active "$service" 2>/dev/null)
    local enabled=$(systemctl is-enabled "$service" 2>/dev/null)
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}SERVICE:${NC} $service"
    
    # Status with color
    if [ "$active" = "active" ]; then
        echo -e "${CYAN}STATUS:${NC}  ${GREEN}✓ Running${NC}"
    elif [ "$active" = "failed" ]; then
        echo -e "${CYAN}STATUS:${NC}  ${RED}✗ Failed${NC}"
    elif [ "$active" = "inactive" ]; then
        echo -e "${CYAN}STATUS:${NC}  ${YELLOW}○ Stopped${NC}"
    else
        echo -e "${CYAN}STATUS:${NC}  ${YELLOW}? $active${NC}"
    fi
    
    # Enabled status
    if [ "$enabled" = "enabled" ]; then
        echo -e "${CYAN}AUTOSTART:${NC} Enabled"
    else
        echo -e "${CYAN}AUTOSTART:${NC} Disabled"
    fi
    
    # If failed or inactive, show why
    if [ "$active" = "failed" ] || [ "$active" = "inactive" ]; then
        echo ""
        echo -e "${YELLOW}Recent logs (last 20 lines):${NC}"
        echo -e "${YELLOW}─────────────────────────────────────────────────────────────${NC}"
        sudo journalctl -u "$service" -n 20 --no-pager | sed 's/^/  /'
        echo -e "${YELLOW}─────────────────────────────────────────────────────────────${NC}"
        
        # Common issues and hints
        echo ""
        echo -e "${YELLOW}Common Issues:${NC}"
        
        case "$service" in
            "tinymedia")
                echo "  • USB drive not mounted at expected location"
                echo "  • Python dependencies missing (Flask, gunicorn)"
                echo "  • Port 5000 already in use"
                echo "  • Check: ls -la /opt/tinymedia"
                echo "  • Check: sudo lsof -i :5000"
                ;;
            "kiwix")
                echo "  • USB drive not mounted"
                echo "  • No .zim files in USB:/kiwix/ folder"
                echo "  • kiwix-serve not installed properly"
                echo "  • Check: mountpoint /media/usb"
                echo "  • Check: ls /media/usb/kiwix/*.zim"
                ;;
            "rtl-fm-radio"|"welle-cli"|"openwebrx"|"dump1090-fa"|"aiscatcher")
                echo "  • RTL-SDR dongle not connected"
                echo "  • Another SDR service using the dongle"
                echo "  • RTL-SDR drivers not installed"
                echo "  • USB permissions issue"
                echo "  • Check: lsusb | grep -i realtek"
                echo "  • Check: rtl_test -t"
                echo "  • Try: ./start-services.sh stop-sdr"
                ;;
            "delling-dashboard")
                echo "  • Python3 not found"
                echo "  • Flask not installed"
                echo "  • Port 1337 already in use"
                echo "  • Missing app.py file"
                echo "  • Check: which python3"
                echo "  • Check: python3 -m flask --version"
                ;;
        esac
    fi
    
    echo ""
}

show_overview() {
    print_header "Service Status Overview"
    
    local running_count=0
    local failed_count=0
    local stopped_count=0
    
    for service in "${ALL_SERVICES[@]}"; do
        if ! systemctl list-unit-files | grep -q "^${service}.service"; then
            continue
        fi
        
        local active=$(systemctl is-active "$service" 2>/dev/null)
        
        if [ "$active" = "active" ]; then
            echo -e "${GREEN}[✓]${NC} $service"
            ((running_count++))
        elif [ "$active" = "failed" ]; then
            echo -e "${RED}[✗]${NC} $service (failed)"
            ((failed_count++))
        else
            echo -e "${YELLOW}[○]${NC} $service (stopped)"
            ((stopped_count++))
        fi
    done
    
    echo ""
    echo "Summary:"
    echo -e "  Running: ${GREEN}$running_count${NC}"
    echo -e "  Failed:  ${RED}$failed_count${NC}"
    echo -e "  Stopped: ${YELLOW}$stopped_count${NC}"
}

check_hardware() {
    print_header "Hardware Check"
    
    echo -e "${CYAN}RTL-SDR Devices:${NC}"
    if lsusb | grep -i "realtek\|0bda:283"; then
        lsusb | grep -i "realtek\|0bda:283" | sed 's/^/  /'
    else
        echo -e "  ${YELLOW}No RTL-SDR devices found${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}USB Mounts:${NC}"
    mount | grep "/media/usb" | sed 's/^/  /' || echo -e "  ${YELLOW}No USB drive mounted at /media/usb${NC}"
    
    echo ""
    echo -e "${CYAN}Network Interfaces:${NC}"
    ip addr show wlan0 2>/dev/null | grep "inet " | sed 's/^/  /' || echo -e "  ${YELLOW}wlan0 not configured${NC}"
}

show_menu() {
    echo ""
    echo "What would you like to check?"
    echo ""
    echo "  1) Overview (all services)"
    echo "  2) Hardware status"
    echo "  3) Detailed diagnosis - Dashboard"
    echo "  4) Detailed diagnosis - Tinymedia"
    echo "  5) Detailed diagnosis - Kiwix"
    echo "  6) Detailed diagnosis - FM Radio"
    echo "  7) Detailed diagnosis - DAB+ Radio"
    echo "  8) Detailed diagnosis - OpenWebRX"
    echo "  9) Detailed diagnosis - ADS-B"
    echo "  10) Detailed diagnosis - AIS"
    echo "  11) Full report (all details)"
    echo ""
    echo "  0) Exit"
    echo ""
}

full_report() {
    print_header "Full Diagnostic Report"
    
    check_hardware
    
    for service in "${ALL_SERVICES[@]}"; do
        check_service_status "$service"
    done
}

main() {
    print_header "Delling Service Diagnostics"
    
    if [ "$1" ]; then
        # Command line argument provided
        case "$1" in
            "overview"|"status")
                show_overview
                ;;
            "hardware"|"hw")
                check_hardware
                ;;
            "full"|"all")
                full_report
                ;;
            "dashboard"|"tinymedia"|"kiwix"|"rtl-fm-radio"|"welle-cli"|"openwebrx"|"dump1090-fa"|"aiscatcher")
                check_service_status "$1"
                ;;
            *)
                echo "Usage: $0 [overview|hardware|full|<service-name>]"
                echo ""
                echo "Available services:"
                echo "  dashboard, tinymedia, kiwix, rtl-fm-radio, welle-cli,"
                echo "  openwebrx, dump1090-fa, aiscatcher"
                exit 1
                ;;
        esac
    else
        # Interactive mode
        while true; do
            show_menu
            read -p "Enter your choice: " choice
            
            case $choice in
                1)
                    show_overview
                    ;;
                2)
                    check_hardware
                    ;;
                3)
                    check_service_status "delling-dashboard"
                    ;;
                4)
                    check_service_status "tinymedia"
                    ;;
                5)
                    check_service_status "kiwix"
                    ;;
                6)
                    check_service_status "rtl-fm-radio"
                    ;;
                7)
                    check_service_status "welle-cli"
                    ;;
                8)
                    check_service_status "openwebrx"
                    ;;
                9)
                    check_service_status "dump1090-fa"
                    ;;
                10)
                    check_service_status "aiscatcher"
                    ;;
                11)
                    full_report
                    ;;
                0)
                    echo "Exiting..."
                    exit 0
                    ;;
                *)
                    echo -e "${RED}Invalid choice. Please try again.${NC}"
                    ;;
            esac
            
            read -p $'\nPress Enter to continue...'
        done
    fi
}

main "$@"
