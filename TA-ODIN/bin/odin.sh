#!/bin/bash
#
# TA-ODIN Discovery Script for Linux
# Scans for known log files and services based on rules in odin_rules_linux.csv
#
# Output format:
# timestamp=<ISO8601>, hostname=<hostname>, os=linux, detection_type=<file|service>, 
# category=<category>, path=<path>, file=<filename>, exists=<true|false>, 
# empty=<true|false>, size_bytes=<size>, description=<description>
#

# Don't use set -e as we want to continue even if services aren't found

# Find script directory (works even with symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
RULES_FILE="$APP_DIR/lookups/odin_rules_linux.csv"

# Get timestamp in ISO 8601 format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%S"
}

# Get hostname
HOSTNAME=$(hostname -f 2>/dev/null || hostname)

# Check if rules file exists
if [[ ! -f "$RULES_FILE" ]]; then
    echo "timestamp=$(get_timestamp), hostname=$HOSTNAME, os=linux, detection_type=error, category=odin, message=\"Rules file not found: $RULES_FILE\""
    exit 1
fi

# Function to check if a service is running
# Supports multiple service name variants (comma-separated)
check_service() {
    local service_names="$1"
    local IFS=','
    
    for service_name in $service_names; do
        # Trim whitespace using parameter expansion
        service_name="${service_name#"${service_name%%[![:space:]]*}"}"
        service_name="${service_name%"${service_name##*[![:space:]]}"}"
        
        # Try systemctl first (modern Linux)
        if command -v systemctl &>/dev/null; then
            if systemctl is-active --quiet "$service_name" 2>/dev/null; then
                echo "running"
                return 0
            fi
        fi
        
        # Try service command (SysV init)
        if command -v service &>/dev/null; then
            if service "$service_name" status &>/dev/null; then
                echo "running"
                return 0
            fi
        fi
        
        # Check if process is running
        if pgrep -x "$service_name" &>/dev/null; then
            echo "running"
            return 0
        fi
    done
    
    echo "not_running"
    return 0  # Return success even if not running - we still want to report the status
}

# Function to check files in a directory
# Supports wildcards and recursive search
check_files() {
    local check_path="$1"
    local file_pattern="$2"
    local category="$3"
    local description="$4"
    
    # Track if we found any valid paths
    local found_any_path=false
    
    # Expand path (handles wildcards)
    for expanded_path in $check_path; do
        # Check if the path actually exists (vs just being the unexpanded glob pattern)
        if [[ ! -e "$expanded_path" ]]; then
            continue
        fi
        
        found_any_path=true
        
        if [[ -d "$expanded_path" ]]; then
            local found_files=0
            local total_size=0
            
            # Handle comma-separated file patterns
            local IFS=','
            for pattern in $file_pattern; do
                # Trim whitespace using parameter expansion
                pattern="${pattern#"${pattern%%[![:space:]]*}"}"
                pattern="${pattern%"${pattern##*[![:space:]]}"}"
                
                # Find files recursively
                while IFS= read -r -d '' file; do
                    if [[ -f "$file" ]]; then
                        found_files=$((found_files + 1))
                        file_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
                        total_size=$((total_size + file_size))
                        
                        # Get relative path from check_path
                        rel_path="${file#$expanded_path}"
                        rel_path="${rel_path#/}"
                        filename=$(basename "$file")
                        
                        echo "timestamp=$(get_timestamp), hostname=$HOSTNAME, os=linux, detection_type=file, category=$category, path=$expanded_path, file=$filename, relative_path=$rel_path, exists=true, empty=false, size_bytes=$file_size, description=\"$description\""
                    fi
                done < <(find "$expanded_path" -type f -name "$pattern" -print0 2>/dev/null)
            done
            
            # If directory exists but no matching files found
            if [[ $found_files -eq 0 ]]; then
                echo "timestamp=$(get_timestamp), hostname=$HOSTNAME, os=linux, detection_type=file, category=$category, path=$expanded_path, file=, exists=true, empty=true, size_bytes=0, description=\"$description\""
            fi
            
        elif [[ -f "$expanded_path" ]]; then
            # Direct file path (not a directory)
            file_size=$(stat -c%s "$expanded_path" 2>/dev/null || stat -f%z "$expanded_path" 2>/dev/null || echo 0)
            filename=$(basename "$expanded_path")
            dirpath=$(dirname "$expanded_path")
            
            if [[ $file_size -gt 0 ]]; then
                echo "timestamp=$(get_timestamp), hostname=$HOSTNAME, os=linux, detection_type=file, category=$category, path=$dirpath, file=$filename, exists=true, empty=false, size_bytes=$file_size, description=\"$description\""
            else
                echo "timestamp=$(get_timestamp), hostname=$HOSTNAME, os=linux, detection_type=file, category=$category, path=$dirpath, file=$filename, exists=true, empty=true, size_bytes=0, description=\"$description\""
            fi
        fi
    done
    
    # If no paths matched at all, report exists=false
    if [[ "$found_any_path" == "false" ]]; then
        echo "timestamp=$(get_timestamp), hostname=$HOSTNAME, os=linux, detection_type=file, category=$category, path=$check_path, file=, exists=false, empty=false, size_bytes=0, description=\"$description\""
    fi
}

# Function to trim whitespace (handles quotes safely)
trim() {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"  # Remove leading whitespace
    var="${var%"${var##*[![:space:]]}"}"  # Remove trailing whitespace
    echo "$var"
}

# Read and process rules file
# Skip header line
tail -n +2 "$RULES_FILE" | while IFS=',' read -r detection_type category check_path check_service file_pattern description; do
    # Trim whitespace from all fields
    detection_type=$(trim "$detection_type")
    category=$(trim "$category")
    check_path=$(trim "$check_path")
    check_service=$(trim "$check_service")
    file_pattern=$(trim "$file_pattern")
    description=$(trim "$description")
    
    # Skip empty lines
    [[ -z "$detection_type" ]] && continue
    
    case "$detection_type" in
        file)
            if [[ -n "$check_path" ]]; then
                # Default to *.log if no pattern specified
                [[ -z "$file_pattern" ]] && file_pattern="*.log"
                check_files "$check_path" "$file_pattern" "$category" "$description"
            fi
            ;;
        service)
            if [[ -n "$check_service" ]]; then
                status=$(check_service "$check_service")
                echo "timestamp=$(get_timestamp), hostname=$HOSTNAME, os=linux, detection_type=service, category=$category, service_name=$check_service, status=$status, description=\"$description\""
            fi
            ;;
    esac
done

# Output a completion marker
echo "timestamp=$(get_timestamp), hostname=$HOSTNAME, os=linux, detection_type=status, category=odin, message=\"Discovery scan completed\""
