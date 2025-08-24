#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display section headers
print_section() {
    echo -e "\n${PURPLE}===== $1 =====${NC}"
}

# Function to display key-value pairs
print_info() {
    printf "%-25s: %s\n" "$1" "$2"
}

# Function to get local system information
get_local_info() {
    clear
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}        Local System Information            ${NC}"
    echo -e "${GREEN}=============================================${NC}"

    # System Information
    print_section "SYSTEM INFORMATION"
    print_info "Hostname" "$(hostname)"
    print_info "Logged-in User" "$(whoami)"
    print_info "Uptime" "$(uptime | awk -F'( |,|:)+' '{if ($7=="min") printf "%d minutes", $6; else printf "%d days, %d hours, %d minutes", $6, $8, $9}')"

    # OS Information
    print_section "OPERATING SYSTEM"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        print_info "Distribution" "$NAME"
        print_info "Version" "$VERSION"
        print_info "ID" "$ID"
        print_info "Codename" "$VERSION_CODENAME"
    fi
    print_info "Kernel Version" "$(uname -r)"
    print_info "Architecture" "$(uname -m)"

    # CPU Information
    print_section "PROCESSOR"
    print_info "CPU Model" "$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
    print_info "CPU Cores" "$(nproc)"
    print_info "CPU Threads" "$(grep -c "processor" /proc/cpuinfo)"
    print_info "CPU MHz" "$(grep -m1 "cpu MHz" /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"

    # Memory Information
    print_section "MEMORY"
    total_mem=$(free -h | awk '/Mem:/ {print $2}')
    used_mem=$(free -h | awk '/Mem:/ {print $3}')
    available_mem=$(free -h | awk '/Mem:/ {print $7}')
    print_info "Total Memory" "$total_mem"
    print_info "Used Memory" "$used_mem"
    print_info "Available Memory" "$available_mem"
    print_info "Swap Total" "$(free -h | awk '/Swap:/ {print $2}')"
    print_info "Swap Used" "$(free -h | awk '/Swap:/ {print $3}')"

    # Disk Information
    print_section "DISK STORAGE"
    echo -e "${YELLOW}Mounted Filesystems:${NC}"
    df -h | grep -E '^/dev/' | awk '{printf "%-25s: %s (%s used, %s free)\n", $6, $2, $5, $4}'

    # Network Information
    print_section "NETWORK"
    echo -e "${YELLOW}Network Interfaces:${NC}"
    ip -o addr show | awk '{print $2, $4}' | while read line; do
        interface=$(echo $line | cut -d' ' -f1)
        ip=$(echo $line | cut -d' ' -f2)
        if [ "$interface" != "lo" ]; then
            print_info "$interface" "$ip"
        fi
    done

    # Graphics Information
    print_section "GRAPHICS"
    if command -v lspci > /dev/null; then
        gpu_info=$(lspci | grep -i vga | cut -d: -f3 | sed 's/^ //')
        if [ -n "$gpu_info" ]; then
            print_info "GPU" "$gpu_info"
        else
            print_info "GPU" "Not detected"
        fi
    else
        print_info "GPU" "lspci command not available"
    fi

    # Peripheral Devices
    print_section "PERIPHERAL DEVICES"
    echo -e "${YELLOW}USB Devices:${NC}"
    if command -v lsusb > /dev/null; then
        lsusb | head -5 | while read line; do
            echo "  $line"
        done
        usb_count=$(lsusb | wc -l)
        echo "  ... and $((usb_count - 5)) more devices"
    else
        echo "  lsusb command not available"
    fi

    # System Temperature (if available)
    print_section "TEMPERATURE"
    if command -v sensors > /dev/null 2>&1; then
        sensors | grep -E '(Package id|Core|temp)' | head -3 | while read line; do
            echo "  $line"
        done
    elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        echo "  CPU Temperature: $((temp/1000))°C"
    else
        echo "  Temperature data not available"
    fi

    # Battery Information (if available)
    print_section "BATTERY"
    if [ -d /sys/class/power_supply ]; then
        batteries=$(find /sys/class/power_supply -name "BAT*")
        if [ -n "$batteries" ]; then
            for bat in $batteries; do
                capacity=$(cat $bat/capacity 2>/dev/null)
                status=$(cat $bat/status 2>/dev/null)
                if [ -n "$capacity" ]; then
                    print_info "Battery ${bat: -1}" "$capacity% ($status)"
                fi
            done
        else
            echo "  No battery detected"
        fi
    else
        echo "  Battery information not available"
    fi

    # Print report generation time
    print_section "REPORT INFO"
    print_info "Report generated on" "$(date)"
    print_info "Script version" "1.0"

    echo -e "\n${GREEN}Local system information report complete!${NC}"
}

# Function to get information about a remote IP
get_remote_info() {
    local ip=$1
    
    clear
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}        Remote System Information           ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    
    print_section "IP ADDRESS INFORMATION"
    print_info "Target IP" "$ip"
    
    # Check if the IP is valid
    if ! [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid IP address format${NC}"
        return 1
    fi
    
    # Check if the host is reachable
    print_section "CONNECTIVITY CHECK"
    echo -n "Pinging host... "
    if ping -c 1 -W 1 "$ip" &> /dev/null; then
        echo -e "${GREEN}Host is reachable${NC}"
    else
        echo -e "${RED}Host is not reachable${NC}"
        echo "Some information may not be available"
    fi
    
    # Get WHOIS information
    print_section "WHOIS INFORMATION"
    if command -v whois &> /dev/null; then
        whois_result=$(whois "$ip" | head -20)
        if [ -n "$whois_result" ]; then
            echo "$whois_result"
            echo "... (output truncated)"
        else
            echo "WHOIS information not available"
        fi
    else
        echo "WHOIS command not installed"
    fi
    
    # Get DNS information
    print_section "DNS INFORMATION"
    if command -v nslookup &> /dev/null; then
        nslookup_result=$(nslookup "$ip" 2>/dev/null)
        if [ -n "$nslookup_result" ]; then
            echo "$nslookup_result"
        else
            echo "DNS information not available"
        fi
    else
        echo "nslookup command not installed"
    fi
    
    # Get open ports information (simplified)
    print_section "COMMON PORTS SCAN"
    echo "Scanning common ports (this may take a moment)..."
    
    # Common ports to check
    ports=(21 22 23 25 53 80 110 135 139 143 443 445 993 995 1723 3306 3389 5900 8080)
    
    for port in "${ports[@]}"; do
        (echo >/dev/tcp/"$ip"/"$port") &>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "Port $port: ${GREEN}Open${NC}"
        else
            echo -e "Port $port: ${RED}Closed${NC}"
        fi
    done
    
    # Get traceroute information
    print_section "NETWORK PATH"
    if command -v traceroute &> /dev/null; then
        echo "Tracing route to $ip (first 5 hops)..."
        traceroute -m 5 "$ip" 2>/dev/null | head -6
    elif command -v tracepath &> /dev/null; then
        echo "Tracing path to $ip (first 5 hops)..."
        tracepath "$ip" 2>/dev/null | head -6
    else
        echo "Traceroute tools not available"
    fi
    
    # Get geographical information (if curl is available)
    print_section "GEOGRAPHICAL INFORMATION"
    if command -v curl &> /dev/null; then
        geo_info=$(curl -s "http://ip-api.com/json/$ip")
        if [ -n "$geo_info" ]; then
            echo "$geo_info" | grep -Eo '"[^"]*":[^,]*' | while read line; do
                key=$(echo $line | cut -d'"' -f2)
                value=$(echo $line | cut -d: -f2 | tr -d '"')
                if [[ "$key" != "status" && "$value" != "success" ]]; then
                    print_info "$key" "$value"
                fi
            done
        else
            echo "Geographical information not available"
        fi
    else
        echo "curl command not available"
    fi
    
    print_section "REPORT INFO"
    print_info "Report generated on" "$(date)"
    print_info "Target IP" "$ip"
    
    echo -e "\n${GREEN}Remote system information report complete!${NC}"
}

# Main menu
show_menu() {
    echo -e "${BLUE}"
    echo "============================================="
    echo "    Linux System Information Tool"
    echo "============================================="
    echo -e "${NC}"
    echo "1. Display Local System Information"
    echo "2. Get Information About a Remote IP"
    echo "3. Exit"
    echo
    read -p "Please select an option [1-3]: " choice
}

# Main script logic
while true; do
    show_menu
    case $choice in
        1)
            get_local_info
            ;;
        2)
            read -p "Enter the IP address to analyze: " ip_address
            get_remote_info "$ip_address"
            ;;
        3)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option, please try again${NC}"
            ;;
    esac
    
    echo
    read -p "Press Enter to continue..."
done
