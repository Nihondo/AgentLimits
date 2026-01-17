#!/bin/bash
# AgentLimits Status Line Script for Claude Code
# Displays usage information from AgentLimits widget data in a single line format.
# Settings are synchronized with the AgentLimits app via App Group.
#
# Usage:
#   ./agentlimits_statusline_claude.sh           # Sync with app settings
#   ./agentlimits_statusline_claude.sh -ja       # Force Japanese
#   ./agentlimits_statusline_claude.sh -en       # Force English
#   ./agentlimits_statusline_claude.sh -r        # Force remaining mode
#   ./agentlimits_statusline_claude.sh -u        # Force used mode
#   ./agentlimits_statusline_claude.sh -i        # Force used+ideal mode
#   ./agentlimits_statusline_claude.sh -d        # Debug output

set -euo pipefail

# App Group identifier
APP_GROUP="group.com.dmng.agentlimit"

# Snapshot file path
SNAPSHOT_FILE="$HOME/Library/Group Containers/${APP_GROUP}/Library/Application Support/AgentLimit/usage_snapshot_claude.json"

# ANSI color codes
GRAY='\033[90m'
RESET_COLOR='\033[0m'

# Default colors (hex)
DEFAULT_COLOR_GREEN="#00FF00"
DEFAULT_COLOR_ORANGE="#FFA500"
DEFAULT_COLOR_RED="#FF0000"

# Default thresholds
DEFAULT_WARNING_THRESHOLD=70
DEFAULT_DANGER_THRESHOLD=90


# Default ideal mode thresholds (excess percentage)
DEFAULT_IDEAL_WARNING_DELTA=0
DEFAULT_IDEAL_DANGER_DELTA=10
# Debug flag (prints detailed settings and parsed values)
DEBUG=false

# App Group preferences plist path (more reliable than defaults on some setups)
PREFS_PLIST="$HOME/Library/Group Containers/${APP_GROUP}/Library/Preferences/${APP_GROUP}.plist"

# Read App Group settings (defaults first, then plist fallback)
read_app_setting() {
    local key="$1"
    local value=""
    value=$(defaults read "$APP_GROUP" "$key" 2>/dev/null) || value=""
    if [[ -z "$value" && -f "$PREFS_PLIST" ]]; then
        value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$PREFS_PLIST" 2>/dev/null) || value=""
    fi
    echo "$value"
}


# Read threshold setting with default
read_threshold() {
    local key="$1"
    local default="$2"
    local value
    value=$(read_app_setting "$key")
    if [[ -z "$value" || ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "$default"
    else
        printf "%.0f" "$value"
    fi
}

# Read color setting with default
read_color() {
    local key="$1"
    local default="$2"
    local value
    value=$(read_app_setting "$key")
    if [[ -z "$value" || ! "$value" =~ ^#[0-9A-Fa-f]{6,8}$ ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Print debug messages when enabled
debug_log() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "[debug] $*" >&2
    fi
}

# Convert hex color to ANSI 24-bit true color escape sequence
hex_to_ansi() {
    local hex="$1"
    hex="${hex#\#}"
    # Extract RGB (ignore alpha if present)
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    echo "\033[38;2;${r};${g};${b}m"
}

# Determine status level based on USED percentage and thresholds
# Always uses used percentage (not remaining) for consistent color determination
# Returns: "green", "orange", or "red"
get_status_level() {
    local used_percent="$1"
    local warning_threshold="$2"
    local danger_threshold="$3"

    # High usage = danger (simple, consistent logic)
    if [[ $used_percent -ge $danger_threshold ]]; then
        echo "red"
    elif [[ $used_percent -ge $warning_threshold ]]; then
        echo "orange"
    else
        echo "green"
    fi
}

# Determine status level for ideal mode (comparison-based)
# Returns: "green", "orange", or "red"
get_ideal_status_level() {
    local used_percent="$1"
    local ideal_percent="$2"
    local warning_delta="$3"
    local danger_delta="$4"
    
    local diff=$((used_percent - ideal_percent))
    
    if [[ $diff -ge $danger_delta ]]; then
        echo "red"
    elif [[ $diff -gt $warning_delta ]]; then
        echo "orange"
    else
        echo "green"
    fi
}

# Get system language
get_system_language() {
    local sys_lang
    sys_lang=$(defaults read -g AppleLanguages 2>/dev/null | tr -d '[:space:]' | sed 's/[()]//g' | cut -d',' -f1 | sed 's/"//g')
    if [[ "$sys_lang" == ja* ]]; then
        echo "ja"
    else
        echo "en"
    fi
}

# Read settings from App Group
APP_DISPLAY_MODE=$(read_app_setting "usage_display_mode_cached")
APP_LANGUAGE=$(read_app_setting "app_language")

# Determine effective language
if [[ "$APP_LANGUAGE" == "ja" ]]; then
    LANG_CODE="ja"
elif [[ "$APP_LANGUAGE" == "en" ]]; then
    LANG_CODE="en"
else
    # System setting or not set
    LANG_CODE=$(get_system_language)
fi

# Determine display mode (default: used, can be overridden later)
if [[ "$APP_DISPLAY_MODE" == "remaining" ]]; then
    DISPLAY_MODE="remaining"
else
    DISPLAY_MODE="used"
fi
DISPLAY_MODE_OVERRIDE=""

# Parse arguments (override app settings)
while [[ $# -gt 0 ]]; do
    case "$1" in
        -ja)
            LANG_CODE="ja"
            shift
            ;;
        -en)
            LANG_CODE="en"
            shift
            ;;
        -r|--remaining)
            DISPLAY_MODE_OVERRIDE="remaining"
            shift
            ;;
        -u|--used)
            DISPLAY_MODE_OVERRIDE="used"
            shift
            ;;
        -i|--ideal)
            DISPLAY_MODE_OVERRIDE="usedWithIdeal"
            shift
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Debug: app-level settings after parsing options
debug_log "app_group=${APP_GROUP}"
debug_log "prefs_plist=${PREFS_PLIST} exists=$([[ -f "$PREFS_PLIST" ]] && echo yes || echo no)"
debug_log "snapshot_file=${SNAPSHOT_FILE} exists=$([[ -f "$SNAPSHOT_FILE" ]] && echo yes || echo no)"
debug_log "app_display_mode_cached=${APP_DISPLAY_MODE:-unset}"
debug_log "app_language=${APP_LANGUAGE:-unset}"
debug_log "lang_code=${LANG_CODE}"
debug_log "display_mode_override=${DISPLAY_MODE_OVERRIDE:-none}"

# Localized strings
if [[ "$LANG_CODE" == "ja" ]]; then
    L_RESET="リセット時間"
    L_UPDATED="更新:"
    L_ERROR_NO_FILE="エラー: スナップショットファイルが見つかりません"
    L_ERROR_NO_JQ="エラー: jqがインストールされていません"
    L_ERROR_PARSE="エラー: JSONのパースに失敗しました"
else
    L_RESET="Resets at"
    L_UPDATED="updated:"
    L_ERROR_NO_FILE="Error: Snapshot file not found"
    L_ERROR_NO_JQ="Error: jq is not installed"
    L_ERROR_PARSE="Error: Failed to parse JSON"
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "$L_ERROR_NO_JQ" >&2
    exit 1
fi

# Check if snapshot file exists
if [[ ! -f "$SNAPSHOT_FILE" ]]; then
    echo "$L_ERROR_NO_FILE" >&2
    exit 1
fi

# Read JSON data
json_data=$(cat "$SNAPSHOT_FILE") || {
    echo "$L_ERROR_PARSE" >&2
    exit 1
}

# Extract values using jq
primary_percent=$(echo "$json_data" | jq -r '.primaryWindow.usedPercent // empty')
primary_reset_at=$(echo "$json_data" | jq -r '.primaryWindow.resetAt // empty')
secondary_percent=$(echo "$json_data" | jq -r '.secondaryWindow.usedPercent // empty')
secondary_reset_at=$(echo "$json_data" | jq -r '.secondaryWindow.resetAt // empty')
primary_window_seconds=$(echo "$json_data" | jq -r '.primaryWindow.limitWindowSeconds // 18000')
secondary_window_seconds=$(echo "$json_data" | jq -r '.secondaryWindow.limitWindowSeconds // 604800')
fetched_at=$(echo "$json_data" | jq -r '.fetchedAt // empty')
snapshot_display_mode=$(echo "$json_data" | jq -r '.displayMode // empty')

# Resolve effective display mode (override > app > snapshot)
if [[ -n "$DISPLAY_MODE_OVERRIDE" ]]; then
    EFFECTIVE_DISPLAY_MODE="$DISPLAY_MODE_OVERRIDE"
elif [[ -n "$APP_DISPLAY_MODE" ]]; then
    EFFECTIVE_DISPLAY_MODE="$APP_DISPLAY_MODE"
elif [[ -n "$snapshot_display_mode" ]]; then
    EFFECTIVE_DISPLAY_MODE="$snapshot_display_mode"
else
    EFFECTIVE_DISPLAY_MODE="used"
fi

if [[ -n "$DISPLAY_MODE_OVERRIDE" ]]; then
    DISPLAY_MODE="$DISPLAY_MODE_OVERRIDE"
elif [[ "$snapshot_display_mode" == "remaining" ]]; then
    DISPLAY_MODE="remaining"
elif [[ "$snapshot_display_mode" == "used" ]]; then
    DISPLAY_MODE="used"
fi

debug_log "snapshot_display_mode=${snapshot_display_mode:-unset}"
debug_log "display_mode_effective=${DISPLAY_MODE}"
debug_log "json.primary.usedPercent=${primary_percent:-unset}"
debug_log "json.primary.resetAt=${primary_reset_at:-unset}"
debug_log "json.secondary.usedPercent=${secondary_percent:-unset}"
debug_log "json.secondary.resetAt=${secondary_reset_at:-unset}"
debug_log "json.fetchedAt=${fetched_at:-unset}"

# Validate required fields
if [[ -z "$primary_percent" || -z "$secondary_percent" || -z "$fetched_at" ]]; then
    echo "$L_ERROR_PARSE" >&2
    exit 1
fi

# Convert ISO8601 date to local time (macOS date command)
convert_iso8601_to_local() {
    local iso_date="$1"
    local format="$2"

    # Remove milliseconds and Z suffix for compatibility
    local clean_date
    clean_date=$(echo "$iso_date" | sed 's/\.[0-9]*Z$/Z/' | sed 's/Z$/+0000/')

    # macOS date command with -j flag
    date -j -f "%Y-%m-%dT%H:%M:%S%z" "$clean_date" +"$format" 2>/dev/null || echo "--:--"
}

# Format updated time (absolute)
# Calculate ideal usage percentage based on elapsed time
# Returns: integer percentage (0-100)
calculate_ideal_percent() {
    local reset_at_iso="$1"
    local window_seconds="$2"
    
    # Convert reset_at to Unix timestamp
    local clean_date
    clean_date=$(echo "$reset_at_iso" | sed 's/.[0-9]*Z$/Z/' | sed 's/Z$/+0000/')
    local reset_ts
    reset_ts=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$clean_date" +"%s" 2>/dev/null)
    
    if [[ -z "$reset_ts" || ! "$reset_ts" =~ ^[0-9]+$ ]]; then
        echo ""  # Return empty when resetAt is unavailable
        return
    fi
    
    # Calculate window start (reset - window_seconds)
    local window_start=$((reset_ts - window_seconds))
    local now_ts
    now_ts=$(date +"%s")
    
    # Calculate elapsed time
    local elapsed=$((now_ts - window_start))
    
    # Calculate ideal percentage
    if [[ $window_seconds -le 0 ]]; then
        echo "50"
        return
    fi
    
    local ideal_percent=$((elapsed * 100 / window_seconds))
    
    # Clamp to 0-100
    if [[ $ideal_percent -lt 0 ]]; then
        ideal_percent=0
    elif [[ $ideal_percent -gt 100 ]]; then
        ideal_percent=100
    fi
    
    echo "$ideal_percent"
}

format_updated_at() {
    local fetched_iso="$1"
    local updated_time
    updated_time=$(convert_iso8601_to_local "$fetched_iso" "%H:%M")
    echo "${L_UPDATED} ${updated_time}"
}

# Format reset times
primary_reset_time=$(convert_iso8601_to_local "$primary_reset_at" "%H:%M")
secondary_reset_time=$(convert_iso8601_to_local "$secondary_reset_at" "%Y-%m-%d %H:%M")

# Format updated time (absolute)
updated_text=$(format_updated_at "$fetched_at")
debug_log "updated_text=${updated_text:-unset}"

# Round percentages to integer
# Snapshot values are stored as used% for consistent color determination
primary_snapshot_int=$(printf "%.0f" "$primary_percent")
secondary_snapshot_int=$(printf "%.0f" "$secondary_percent")

# Snapshot always contains used % (no conversion needed)
primary_used_int=$primary_snapshot_int
secondary_used_int=$secondary_snapshot_int

# Read thresholds for Claude Code
PRIMARY_WARNING=$(read_threshold "usage_color_threshold_warning_claudeCode_primary" "$DEFAULT_WARNING_THRESHOLD")
PRIMARY_DANGER=$(read_threshold "usage_color_threshold_danger_claudeCode_primary" "$DEFAULT_DANGER_THRESHOLD")
SECONDARY_WARNING=$(read_threshold "usage_color_threshold_warning_claudeCode_secondary" "$DEFAULT_WARNING_THRESHOLD")
SECONDARY_DANGER=$(read_threshold "usage_color_threshold_danger_claudeCode_secondary" "$DEFAULT_DANGER_THRESHOLD")

# Read ideal mode thresholds
IDEAL_WARNING_DELTA=$(read_threshold "ideal_mode_warning_delta" "$DEFAULT_IDEAL_WARNING_DELTA")
IDEAL_DANGER_DELTA=$(read_threshold "ideal_mode_danger_delta" "$DEFAULT_IDEAL_DANGER_DELTA")

# Read color settings
COLOR_GREEN=$(read_color "usage_color_green" "$DEFAULT_COLOR_GREEN")
COLOR_ORANGE=$(read_color "usage_color_orange" "$DEFAULT_COLOR_ORANGE")
COLOR_RED=$(read_color "usage_color_red" "$DEFAULT_COLOR_RED")

debug_log "thresholds.primary warning=${PRIMARY_WARNING} danger=${PRIMARY_DANGER}"
debug_log "thresholds.secondary warning=${SECONDARY_WARNING} danger=${SECONDARY_DANGER}"
debug_log "colors green=${COLOR_GREEN} orange=${COLOR_ORANGE} red=${COLOR_RED}"
debug_log "ideal_thresholds warning_delta=${IDEAL_WARNING_DELTA} danger_delta=${IDEAL_DANGER_DELTA}"

# Convert hex colors to ANSI escape sequences
ANSI_GREEN=$(hex_to_ansi "$COLOR_GREEN")
ANSI_ORANGE=$(hex_to_ansi "$COLOR_ORANGE")
ANSI_RED=$(hex_to_ansi "$COLOR_RED")

# Determine status levels based on USED percentages (before display mode conversion)
# For usedWithIdeal mode, use comparison-based logic
if [[ "$EFFECTIVE_DISPLAY_MODE" == "usedWithIdeal" ]]; then
    # Calculate ideal percentages
    primary_ideal_int=$(calculate_ideal_percent "$primary_reset_at" "$primary_window_seconds")
    secondary_ideal_int=$(calculate_ideal_percent "$secondary_reset_at" "$secondary_window_seconds")
    
    # Use ideal mode status calculation only if ideal percent is available
    if [[ -n "$primary_ideal_int" ]]; then
        primary_status=$(get_ideal_status_level "$primary_used_int" "$primary_ideal_int" "$IDEAL_WARNING_DELTA" "$IDEAL_DANGER_DELTA")
    else
        primary_status=$(get_status_level "$primary_used_int" "$PRIMARY_WARNING" "$PRIMARY_DANGER")
    fi
    if [[ -n "$secondary_ideal_int" ]]; then
        secondary_status=$(get_ideal_status_level "$secondary_used_int" "$secondary_ideal_int" "$IDEAL_WARNING_DELTA" "$IDEAL_DANGER_DELTA")
    else
        secondary_status=$(get_status_level "$secondary_used_int" "$SECONDARY_WARNING" "$SECONDARY_DANGER")
    fi
    
    debug_log "ideal_mode.primary used=${primary_used_int} ideal=${primary_ideal_int:-N/A} status=${primary_status}"
    debug_log "ideal_mode.secondary used=${secondary_used_int} ideal=${secondary_ideal_int:-N/A} status=${secondary_status}"
else
    primary_status=$(get_status_level "$primary_used_int" "$PRIMARY_WARNING" "$PRIMARY_DANGER")
    secondary_status=$(get_status_level "$secondary_used_int" "$SECONDARY_WARNING" "$SECONDARY_DANGER")
fi

# Apply display mode conversion for display
if [[ "$DISPLAY_MODE" == "remaining" ]]; then
    primary_percent_int=$((100 - primary_used_int))
    secondary_percent_int=$((100 - secondary_used_int))
else
    primary_percent_int=$primary_used_int
    secondary_percent_int=$secondary_used_int
fi

debug_log "computed.primary used=${primary_used_int} display=${primary_percent_int} status=${primary_status}"
debug_log "computed.secondary used=${secondary_used_int} display=${secondary_percent_int} status=${secondary_status}"

# Get ANSI color for status level
get_status_color() {
    case "$1" in
        green)  echo "$ANSI_GREEN" ;;
        orange) echo "$ANSI_ORANGE" ;;
        red)    echo "$ANSI_RED" ;;
        *)      echo "" ;;
    esac
}

primary_color=$(get_status_color "$primary_status")
secondary_color=$(get_status_color "$secondary_status")

# Format percentage text based on display mode
if [[ "$EFFECTIVE_DISPLAY_MODE" == "usedWithIdeal" ]]; then
    # Show used(ideal)% format, or just used% if ideal is unavailable
    if [[ -n "$primary_ideal_int" ]]; then
        primary_text="${primary_used_int}(${primary_ideal_int})%"
    else
        primary_text="${primary_used_int}%"
    fi
    if [[ -n "$secondary_ideal_int" ]]; then
        secondary_text="${secondary_used_int}(${secondary_ideal_int})%"
    else
        secondary_text="${secondary_used_int}%"
    fi
else
    primary_text="${primary_percent_int}%"
    secondary_text="${secondary_percent_int}%"
fi

# Output formatted string with colored percentages and gray reset times/updated time
echo -e "🕔 5h: ${primary_color}${primary_text}${RESET_COLOR} ${GRAY}(${L_RESET} ${primary_reset_time})${RESET_COLOR} / 📅 1w: ${secondary_color}${secondary_text}${RESET_COLOR} ${GRAY}(${L_RESET} ${secondary_reset_time})${RESET_COLOR} - ${GRAY}${updated_text}${RESET_COLOR}"
