#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Delling Service Starter
# Starts all Delling services with status feedback
# ═══════════════════════════════════════════════════════════════════════════

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Service arrays
ALWAYS_ON_SERVICES=(
    "delling-dashboard"
    "tinymedia"
    "kiwix"
)

SDR_SERVICES=(
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

start_service() {
    local service=$1
    local type=$2
    
    # Check if service exists
    if ! systemctl list-unit-files | grep -q "^${service}.service"; then
        echo -e "${YELLOW}[SKIP]${NC} $service (not installed)"
        return
    fi
    
    # Check if already running
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}[RUNNING]${NC} $service (already active)"
        return
    fi
    
    # Try to start the service
    if sudo systemctl start "$service" 2>/dev/null; then
        # Give it a moment to start
        sleep 1
        
        # Verify it's running
        if systemctl is-active --quiet "$service"; then
            echo -e "${GREEN}[STARTED]${NC} $service"
        else
            echo -e "${RED}[FAILED]${NC} $service (started but died immediately)"
        fi
    else
        echo -e "${RED}[ERROR]${NC} $service (failed to start)"
    fi
}

stop_all_sdr() {
    print_header "Stopping Conflicting SDR Services"
    
    for service in "${SDR_SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            echo -e "${YELLOW}[STOPPING]${NC} $service"
            sudo systemctl stop "$service" 2>/dev/null
        fi
    done
    
    # Extra wait for hardware to release
    sleep 2
    echo -e "${GREEN}[DONE]${NC} All SDR services stopped"
}

start_always_on() {
    print_header "Starting Always-On Services"
    
    for service in "${ALWAYS_ON_SERVICES[@]}"; do
        start_service "$service" "always-on"
    done
}

start_specific_sdr() {
    local service=$1
    
    print_header "Starting SDR Service: $service"
    
    # Stop all SDR services first (they conflict for hardware)
    stop_all_sdr
    
    # Start the requested service
    start_service "$service" "sdr"
}

show_menu() {
    echo ""
    echo "What would you like to start?"
    echo ""
    echo "Always-On Services:"
    echo "  1) All always-on services (dashboard, tinymedia, kiwix)"
    echo ""
    echo "SDR Services (hardware exclusive - only one at a time):"
    echo "  2) FM/VHF Radio (rtl-fm-radio)"
    echo "  3) DAB+ Radio (welle-cli)"
    echo "  4) OpenWebRX+ (general SDR web interface)"
    echo "  5) ADS-B Aircraft Tracking (dump1090-fa)"
    echo "  6) AIS Ship Tracking (aiscatcher)"
    echo ""
    echo "  0) Exit"
    echo ""
}

main() {
    print_header "Delling Service Starter"
    
    if [ "$1" ]; then
        # Command line argument provided
        case "$1" in
            "all")
                start_always_on
                ;;
            "fm"|"radio")
                start_specific_sdr "rtl-fm-radio"
                ;;
            "dab")
                start_specific_sdr "welle-cli"
                ;;
            "openwebrx"|"sdr")
                start_specific_sdr "openwebrx"
                ;;
            "adsb"|"aircraft")
                start_specific_sdr "dump1090-fa"
                ;;
            "ais"|"ships")
                start_specific_sdr "aiscatcher"
                ;;
            "stop-sdr")
                stop_all_sdr
                ;;
            *)
                echo "Usage: $0 [all|fm|dab|openwebrx|adsb|ais|stop-sdr]"
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
                    start_always_on
                    ;;
                2)
                    start_specific_sdr "rtl-fm-radio"
                    ;;
                3)
                    start_specific_sdr "welle-cli"
                    ;;
                4)
                    start_specific_sdr "openwebrx"
                    ;;
                5)
                    start_specific_sdr "dump1090-fa"
                    ;;
                6)
                    start_specific_sdr "aiscatcher"
                    ;;
                0)
                    echo "Exiting..."
                    exit 0
                    ;;
                *)
                    echo -e "${RED}Invalid choice. Please try again.${NC}"
                    ;;
            esac
        done
    fi
    
    echo ""
    echo -e "${GREEN}Done!${NC} Use ./diagnose-services.sh to check service status"
}

main "$@"
