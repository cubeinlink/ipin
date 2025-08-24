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
    printf "%-20s: %s\n" "$1" "$2"
}

# Get network interface information
get_network_info() {
    print_section "NETWORK INTERFACES"
    ip -o addr show | grep -v "lo" | while read line; do
        interface=$(echo $line | awk '{print $2}')
        ip=$(echo $line | awk '{print $4}' | cut -d'/' -f1)
        if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then
            print_info "$interface" "$ip"
        fi
    done
}

# Get gateway information
get_gateway_info() {
    print_section "GATEWAY INFORMATION"
    gateway=$(ip route | grep default | awk '{print $3}')
    if [ -n "$gateway" ]; then
        print_info "Default Gateway" "$gateway"
        # Get gateway MAC address if possible
        gateway_mac=$(arp -n $gateway 2>/dev/null | awk '{print $3}' | grep -v "HWaddress")
        if [ -n "$gateway_mac" ]; then
            print_info "Gateway MAC" "$gateway_mac"
        fi
    else
        echo "No default gateway found"
    fi
}

# Scan local network for devices
scan_network() {
    local network=$1
    print_section "SCANNING NETWORK: $network"
    
    echo -e "${YELLOW}Scanning... This may take a few minutes${NC}"
    
    # Create a temporary file for results
    temp_file=$(mktemp)
    
    # Use nmap if available for detailed scanning
    if command -v nmap &> /dev/null; then
        echo -e "${GREEN}Using nmap for detailed scan...${NC}"
        sudo nmap -sn $network/24 | grep -E "(Nmap scan|MAC Address)" > $temp_file
    else
        # Fallback to ping scan
        echo -e "${YELLOW}nmap not found, using ping scan...${NC}"
        for i in {1..254}; do
            ip="${network%.*}.$i"
            ping -c 1 -W 1 $ip &> /dev/null &
        done
        wait
        
        # Get ARP table entries
        arp -a | grep -v "incomplete" > $temp_file
    fi
    
    # Process and display results
    print_section "DEVICES FOUND ON NETWORK"
    
    if [ -s "$temp_file" ]; then
        if command -v nmap &> /dev/null; then
            # Process nmap output
            while read line; do
                if [[ $line == *"Nmap scan"* ]]; then
                    ip=$(echo $line | awk '{print $5}')
                    name=$(echo $line | awk '{print $6}' | tr -d '()')
                elif [[ $line == *"MAC Address"* ]]; then
                    mac=$(echo $line | awk '{print $3}')
                    vendor=$(echo $line | cut -d' ' -f4-)
                    printf "%-15s | %-17s | %-20s | %s\n" "$ip" "$mac" "$name" "$vendor"
                fi
            done < $temp_file
        else
            # Process arp output
            echo -e "${YELLOW}IP Address      | MAC Address       | Hostname${NC}"
            echo -e "${YELLOW}--------------- | ----------------- | -----------------${NC}"
            while read line; do
                ip=$(echo $line | awk '{print $2}' | tr -d '()')
                mac=$(echo $line | awk '{print $4}')
                name=$(echo $line | awk '{print $1}')
                printf "%-15s | %-17s | %s\n" "$ip" "$mac" "$name"
            done < $temp_file
        fi
    else
        echo -e "${RED}No devices found or scan failed${NC}"
    fi
    
    # Clean up
    rm -f $temp_file
}

# Get detailed information about a specific device
get_device_details() {
    local ip=$1
    
    print_section "DETAILED INFORMATION FOR: $ip"
    
    # Check if device is online
    if ping -c 1 -W 1 $ip &> /dev/null; then
        echo -e "${GREEN}Device is online${NC}"
        
        # Get MAC address
        mac=$(arp -n $ip 2>/dev/null | awk '{print $3}' | grep -v "Address")
        if [ -n "$mac" ]; then
            print_info "MAC Address" "$mac"
        fi
        
        # Try to get hostname
        hostname=$(nslookup $ip 2>/dev/null | grep "name" | tail -1 | awk '{print $4}')
        if [ -n "$hostname" ]; then
            print_info "Hostname" "$hostname"
        fi
        
        # Try to get device manufacturer from MAC
        if [ -n "$mac" ]; then
            oui=$(echo $mac | tr -d ':' | cut -c1-6 | tr '[:lower:]' '[:upper:]')
            manufacturer=$(curl -s "https://api.macvendors.com/$oui" 2>/dev/null)
            if [ -n "$manufacturer" ] && [ "$manufacturer" != "Not Found" ]; then
                print_info "Manufacturer" "$manufacturer"
            fi
        fi
        
        # Port scanning (limited to common ports)
        print_info "Port Scan" "Common ports (22,80,443,445)"
        for port in 22 80 443 445; do
            (echo >/dev/tcp/$ip/$port) &>/dev/null
            if [ $? -eq 0 ]; then
                case $port in
                    22) print_info "  Port $port" "SSH (Open)" ;;
                    80) print_info "  Port $port" "HTTP (Open)" ;;
                    443) print_info "  Port $port" "HTTPS (Open)" ;;
                    445) print_info "  Port $port" "SMB (Open)" ;;
                esac
            fi
        done
        
    else
        echo -e "${RED}Device is offline${NC}"
    fi
}

# Main menu
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}=============================================${NC}"
        echo -e "${BLUE}        Network Device Discovery Tool        ${NC}"
        echo -e "${BLUE}=============================================${NC}"
        
        get_network_info
        get_gateway_info
        
        echo -e "\n${GREEN}Options:${NC}"
        echo "1. Scan my local network for devices"
        echo "2. Scan specific network"
        echo "3. Get detailed info about specific device"
        echo "4. Exit"
        
        read -p "Choose an option [1-4]: " choice
        
        case $choice in
            1)
                # Get first non-loopback IP
                network_ip=$(ip -o addr show | grep -v "lo" | grep -v "127.0.0.1" | head -1 | awk '{print $4}' | cut -d'/' -f1)
                if [ -n "$network_ip" ]; then
                    network="${network_ip%.*}.0"
                    scan_network "$network"
                else
                    echo -e "${RED}Could not detect network IP${NC}"
                fi
                ;;
            2)
                read -p "Enter network to scan (e.g., 192.168.1.0): " network
                if [[ $network =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    scan_network "$network"
                else
                    echo -e "${RED}Invalid network address${NC}"
                fi
                ;;
            3)
                read -p "Enter device IP address: " device_ip
                if [[ $device_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    get_device_details "$device_ip"
                else
                    echo -e "${RED}Invalid IP address${NC}"
                fi
                ;;
            4)
         
       echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
        
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read
    done
}

# Check requirements
check_requirements() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}Warning: Some features may require root privileges${NC}"
    fi
    
    if ! command -v ip &> /dev/null; then
        echo -e "${RED}Error: 'ip' command not found${NC}"
        exit 1
    fi
}

# Main execution
check_requirements
main_menu
