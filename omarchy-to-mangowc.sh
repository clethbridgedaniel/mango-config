#!/usr/bin/env bash
# Omarchy to MangoWC Theme Converter v0.3
# Converts all Omarchy themes from ~/.config/omarchy/themes to MangoWC format
# Properly handles symbolic links

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMARCHY_THEMES_DIR="${HOME}/.config/omarchy/themes"
OUTPUT_DIR="${HOME}/.config/mango/themes"
VERBOSE=false
DRY_RUN=false
INTERACTIVE=false
SELECTED_THEMES=()
CONVERSION_STATS=()
FOLLOW_SYMLINKS=false
RESOLVE_SYMLINKS=true

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1"
    fi
}

log_debug() {
    if [[ "$DEBUG" == true ]]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $1"
    fi
}

# Display help information
show_help() {
    cat << EOF
Omarchy to MangoWC Bulk Theme Converter v2.1

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -s, --source DIR         Source directory containing Omarchy themes (default: ~/.config/omarchy/themes)
    -o, --output DIR         Output directory for MangoWC themes (default: ~/.config/mango/themes)
    -t, --themes THEME1,THEME2 Comma-separated list of specific themes to convert
    -v, --verbose            Enable verbose output
    -d, --dry-run            Show what would be converted without actually converting
    -i, --interactive        Interactive mode - select themes to convert
    -L, --follow-symlinks    Follow symbolic links when discovering themes
    -r, --resolve-symlinks   Resolve symlinks to their real paths (default: true)
    -h, --help               Show this help message

EXAMPLES:
    # Convert all themes in default directory
    $0

    # Convert specific themes only
    $0 --themes "bauhaus,nagai-poolside"

    # Follow symlinks when discovering themes
    $0 --follow-symlinks

    # Resolve symlinks to real paths (default behavior)
    $0 --resolve-symlinks

DESCRIPTION:
    This script automatically discovers and converts all Omarchy themes to MangoWC format:
    - Scans ~/.config/omarchy/themes for theme directories
    - Properly handles symbolic links
    - Converts each theme with palette.yml to MangoWC format
    - Generates configurations for MangoWC, Waybar, terminals, etc.
    - Creates installation scripts for each theme
    - Provides batch conversion with statistics

SYMLINK OPTIONS:
    --follow-symlinks    Follow directory symlinks when discovering themes
    --resolve-symlinks   Resolve symlinks to their real paths (default: enabled)

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--source)
                OMARCHY_THEMES_DIR="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -t|--themes)
                IFS=',' read -ra SELECTED_THEMES <<< "$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -i|--interactive)
                INTERACTIVE=true
                shift
                ;;
            -L|--follow-symlinks)
                FOLLOW_SYMLINKS=true
                shift
                ;;
            -r|--resolve-symlinks)
                RESOLVE_SYMLINKS=true
                shift
                ;;
            --no-resolve-symlinks)
                RESOLVE_SYMLINKS=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                log_error "Unexpected argument: $1"
                show_help
                exit 1
                ;;
        esac
    done

    log_verbose "Source directory: $OMARCHY_THEMES_DIR"
    log_verbose "Output directory: $OUTPUT_DIR"
    log_verbose "Interactive mode: $INTERACTIVE"
    log_verbose "Dry run mode: $DRY_RUN"
    log_verbose "Follow symlinks: $FOLLOW_SYMLINKS"
    log_verbose "Resolve symlinks: $RESOLVE_SYMLINKS"
}

# Resolve a path to its real location
resolve_path() {
    local path="$1"
    
    if [[ "$RESOLVE_SYMLINKS" == true ]]; then
        local resolved_path
        resolved_path=$(realpath "$path" 2>/dev/null || echo "$path")
        echo "$resolved_path"
    else
        echo "$path"
    fi
}

# Check if a path is a symlink
is_symlink() {
    local path="$1"
    [[ -L "$path" ]]
}

# Discover available themes with proper symlink handling
discover_themes() {
    log_info "Discovering Omarchy themes in: $OMARCHY_THEMES_DIR"
    
    local themes=()
    local seen_themes=()  # Track seen themes to avoid duplicates
    local find_opts=()
    
    # Set find options based on symlink settings
    if [[ "$FOLLOW_SYMLINKS" == true ]]; then
        find_opts+=("-L")
    fi
    
    # Find all theme directories
    while IFS= read -r -d '' theme_dir; do
        local theme_name
        theme_name=$(basename "$theme_dir")
        local palette_file="$theme_dir/palette.yml"
        
        # Resolve the path if needed
        local resolved_theme_dir
        resolved_theme_dir=$(resolve_path "$theme_dir")
        
        # Check if we've already processed this theme
        local already_seen=false
        for seen in "${seen_themes[@]}"; do
            if [[ "$seen" == "$resolved_theme_dir" ]]; then
                already_seen=true
                break
            fi
        done
        
        if [[ "$already_seen" == true ]]; then
            log_verbose "Skipping duplicate theme (symlink): $theme_name -> $resolved_theme_dir"
            continue
        fi
        
        # Add to seen themes
        seen_themes+=("$resolved_theme_dir")
        
        # Check if palette.yml exists (follow symlinks if needed)
        if [[ -f "$palette_file" ]]; then
            themes+=("$theme_name")
            log_verbose "Found valid theme: $theme_name"
            
            # Log symlink information
            if is_symlink "$theme_dir"; then
                local target
                target=$(readlink "$theme_dir")
                log_verbose "  Theme directory is a symlink: $theme_name -> $target"
            fi
            
            if is_symlink "$palette_file"; then
                local target
                target=$(readlink "$palette_file")
                log_verbose "  Palette file is a symlink: palette.yml -> $target"
            fi
        else
            log_verbose "Skipping directory without palette.yml: $theme_name"
        fi
    done < <(find "${find_opts[@]}" "$OMARCHY_THEMES_DIR" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)

    if [[ ${#themes[@]} -eq 0 ]]; then
        log_warning "No valid themes found in $OMARCHY_THEMES_DIR"
        log_info "Make sure theme directories contain palette.yml files"
        exit 1
    fi

    log_success "Found ${#themes[@]} themes: ${themes[*]}"
    printf '%s\n' "${themes[@]}"
}

# Parse palette.yml with proper symlink handling
parse_palette() {
    local theme_dir="$1"
    local palette_file="$theme_dir/palette.yml"
    
    log_verbose "Parsing palette file: $palette_file"
    
    # Resolve palette file if needed
    local resolved_palette_file
    resolved_palette_file=$(resolve_path "$palette_file")
    
    if [[ ! -f "$resolved_palette_file" ]]; then
        log_error "Resolved palette file does not exist: $resolved_palette_file"
        return 1
    fi
    
    # Log symlink information
    if is_symlink "$palette_file"; then
        local target
        target=$(readlink "$palette_file")
        log_verbose "Following palette symlink: $palette_file -> $target"
    fi

    # Declare associative arrays for color mapping
    declare -gA colors
    declare -gA ansi_colors
    declare -gA ansi_bright_colors
    declare -gA ansi_dim_colors

    # Parse main colors
    local main_colors
    main_colors=$(yq eval '. | to_entries | .[] | "\(.key)=\(.value)"' "$resolved_palette_file" 2>/dev/null || {
        log_error "Failed to parse palette.yml in $theme_dir"
        return 1
    })

    while IFS='=' read -r key value; do
        if [[ -n "$key" && -n "$value" ]]; then
            colors["$key"]="$value"
            log_debug "Parsed color: $key = $value"
        fi
    done <<< "$main_colors"

    # Parse ANSI colors if they exist
    if yq eval '.ansi_normal' "$resolved_palette_file" &>/dev/null; then
        local ansi_normal
        ansi_normal=$(yq eval '.ansi_normal | to_entries | .[] | "\(.key)=\(.value)"' "$resolved_palette_file")
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                ansi_colors["$key"]="$value"
                log_debug "Parsed ANSI color: $key = $value"
            fi
        done <<< "$ansi_normal"
    fi

    if yq eval '.ansi_bright' "$resolved_palette_file" &>/dev/null; then
        local ansi_bright
        ansi_bright=$(yq eval '.ansi_bright | to_entries | .[] | "\(.key)=\(.value)"' "$resolved_palette_file")
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                ansi_bright_colors["$key"]="$value"
                log_debug "Parsed ANSI bright color: $key = $value"
            fi
        done <<< "$ansi_bright"
    fi

    if yq eval '.ansi_dim' "$resolved_palette_file" &>/dev/null; then
        local ansi_dim
        ansi_dim=$(yq eval '.ansi_dim | to_entries | .[] | "\(.key)=\(.value)"' "$resolved_palette_file")
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                ansi_dim_colors["$key"]="$value"
                log_debug "Parsed ANSI dim color: $key = $value"
            fi
        done <<< "$ansi_dim"
    fi

    log_verbose "Palette parsing completed for $(basename "$theme_dir")"
}

# Copy files with proper symlink handling
copy_file_safely() {
    local source="$1"
    local dest="$2"
    
    if [[ ! -e "$source" ]]; then
        log_warning "Source file does not exist: $source"
        return 1
    fi
    
    # Resolve source path if needed
    local resolved_source
    resolved_source=$(resolve_path "$source")
    
    # Create destination directory if needed
    mkdir -p "$(dirname "$dest")"
    
    if is_symlink "$source"; then
        local target
        target=$(readlink "$source")
        log_verbose "Copying symlink target: $source -> $target -> $dest"
        
        # Copy the target file, not the symlink
        cp "$resolved_source" "$dest"
    else
        log_verbose "Copying regular file: $source -> $dest"
        cp "$source" "$dest"
    fi
}

# Generate terminal configurations with symlink handling
generate_terminal_configs() {
    local theme_output_dir="$1"
    local theme_name="$2"
    local theme_source_dir="$3"
    
    log_verbose "Generating terminal configurations for $theme_name"

    # Generate Alacritty config
    if [[ -f "$theme_source_dir/alacritty.toml" ]]; then
        copy_file_safely "$theme_source_dir/alacritty.toml" "$theme_output_dir/alacritty.toml"
        log_verbose "Copied Alacritty configuration"
    else
        generate_alacritty_config "$theme_output_dir" "$theme_name"
    fi

    # Generate Kitty config
    if [[ -f "$theme_source_dir/kitty.conf" ]]; then
        copy_file_safely "$theme_source_dir/kitty.conf" "$theme_output_dir/kitty.conf"
        log_verbose "Copied Kitty configuration"
    else
        generate_kitty_config "$theme_output_dir" "$theme_name"
    fi

    # Generate Ghostty config
    if [[ -f "$theme_source_dir/ghostty.conf" ]]; then
        copy_file_safely "$theme_source_dir/ghostty.conf" "$theme_output_dir/ghostty.conf"
        log_verbose "Copied Ghostty configuration"
    fi
}

# Generate Alacritty configuration
generate_alacritty_config() {
    local theme_output_dir="$1"
    local theme_name="$2"
    local config_file="$theme_output_dir/alacritty.toml"

    cat > "$config_file" << EOF
# Alacritty Theme: $theme_name
# Converted from Omarchy theme
# Generated on: $(date)

[colors.primary]
background = "${colors[primary_bg]:-$101318}"
foreground = "${colors[text_primary]:-$EAEFF5}"

[colors.cursor]
text = "${colors[primary_bg]:-$101318}"
cursor = "${colors[primary_accent]:-$E37B66}"

[colors.normal]
black = "${ansi_colors[black]:-$101318}"
red = "${ansi_colors[red]:-$CB886D}"
green = "${ansi_colors[green]:-$789FA2}"
yellow = "${ansi_colors[yellow]:-$E7A46F}"
blue = "${ansi_colors[blue]:-$8999AA}"
magenta = "${ansi_colors[magenta]:-$E37B66}"
cyan = "${ansi_colors[cyan]:-$809D9E}"
white = "${ansi_colors[white]:-$C6CED8}"

[colors.bright]
black = "${ansi_bright_colors[black]:-$222733}"
red = "${ansi_bright_colors[red]:-$E37B66}"
green = "${ansi_bright_colors[green]:-$809D9E}"
yellow = "${ansi_bright_colors[yellow]:-$E0A568}"
blue = "${ansi_bright_colors[blue]:-$8999AA}"
magenta = "${ansi_bright_colors[magenta]:-$E37B66}"
cyan = "${ansi_bright_colors[cyan]:-$809D9E}"
white = "${ansi_bright_colors[white]:-$EAEFF5}"

[colors.dim]
black = "${ansi_dim_colors[black]:-$101318}"
red = "${ansi_dim_colors[red]:-$CB886D}"
green = "${ansi_dim_colors[green]:-$789FA2}"
yellow = "${ansi_dim_colors[yellow]:-$E7A46F}"
blue = "${ansi_dim_colors[blue]:-$8999AA}"
magenta = "${ansi_dim_colors[magenta]:-$E37B66}"
cyan = "${ansi_dim_colors[cyan]:-$809D9E}"
white = "${ansi_dim_colors[white]:-$C6CED8}"

EOF

    log_verbose "Alacritty configuration generated: $config_file"
}

# Generate Kitty configuration
generate_kitty_config() {
    local theme_output_dir="$1"
    local theme_name="$2"
    local config_file="$theme_output_dir/kitty.conf"

    cat > "$config_file" << EOF
# Kitty Theme: $theme_name
# Converted from Omarchy theme
# Generated on: $(date)

foreground ${colors[text_primary]:-$EAEFF5}
background ${colors[primary_bg]:-$101318}
cursor ${colors[primary_accent]:-$E37B66}

color0 ${ansi_colors[black]:-$101318}
color1 ${ansi_colors[red]:-$CB886D}
color2 ${ansi_colors[green]:-$789FA2}
color3 ${ansi_colors[yellow]:-$E7A46F}
color4 ${ansi_colors[blue]:-$8999AA}
color5 ${ansi_colors[magenta]:-$E37B66}
color6 ${ansi_colors[cyan]:-$809D9E}
color7 ${ansi_colors[white]:-$C6CED8}

color8 ${ansi_bright_colors[black]:-$222733}
color9 ${ansi_bright_colors[red]:-$E37B66}
color10 ${ansi_bright_colors[green]:-$809D9E}
color11 ${ansi_bright_colors[yellow]:-$E0A568}
color12 ${ansi_bright_colors[blue]:-$8999AA}
color13 ${ansi_bright_colors[magenta]:-$E37B66}
color14 ${ansi_bright_colors[cyan]:-$809D9E}
color15 ${ansi_bright_colors[white]:-$EAEFF5}

EOF

    log_verbose "Kitty configuration generated: $config_file"
}

# Generate MangoWC configuration file
generate_mangowc_config() {
    local theme_output_dir="$1"
    local theme_name="$2"
    local config_file="$theme_output_dir/config.conf"

    log_verbose "Generating MangoWC configuration for $theme_name"

    cat > "$config_file" << EOF
# MangoWC Theme: $theme_name
# Converted from Omarchy theme
# Generated on: $(date)

# Window Manager Colors
window_border_color_active ${colors[primary_accent]:-$E37B66}
window_border_color_inactive ${colors[tertiary_bg]:-$222733}
window_border_color_urgent ${colors[error]:-$CB886D}

# Background Colors
background_color ${colors[primary_bg]:-$101318}

# Text Colors
text_color_active ${colors[text_primary]:-$EAEFF5}
text_color_inactive ${colors[text_secondary]:-$C6CED8}
text_color_urgent ${colors[error]:-$CB886D}

# Selection Colors
selection_color ${colors[selection_bg]:-$2B3040}
selection_text_color ${colors[text_primary]:-$EAEFF5}

# Tag Colors
tag_bg_color ${colors[secondary_bg]:-$161B22}
tag_fg_color ${colors[text_secondary]:-$C6CED8}
tag_active_bg_color ${colors[primary_accent]:-$E37B66}
tag_active_fg_color ${colors[primary_bg]:-$101318}
tag_urgent_bg_color ${colors[error]:-$CB886D}
tag_urgent_fg_color ${colors[text_primary]:-$EAEFF5}

# Layout Colors
layout_border_color ${colors[tertiary_accent]:-$809D9E}
layout_fg_color ${colors[text_primary]:-$EAEFF5}

# Bar Colors
bar_bg_color ${colors[secondary_bg]:-$161B22}
bar_fg_color ${colors[text_primary]:-$EAEFF5}
bar_border_color ${colors[tertiary_bg]:-$222733}

# Notification Colors
notification_bg_color ${colors[secondary_bg]:-$161B22}
notification_fg_color ${colors[text_primary]:-$EAEFF5}
notification_border_color ${colors[primary_accent]:-$E37B66}

# Prompt Colors
prompt_bg_color ${colors[tertiary_bg]:-$222733}
prompt_fg_color ${colors[text_primary]:-$EAEFF5}
prompt_border_color ${colors[primary_accent]:-$E37B66}

# State Colors
state_active_color ${colors[success]:-$789FA2}
state_urgent_color ${colors[error]:-$CB886D}
state_inactive_color ${colors[text_dim]:-$98A0AE}

EOF

    log_verbose "MangoWC configuration generated: $config_file"
}

# Generate Waybar style configuration
generate_waybar_style() {
    local theme_output_dir="$1"
    local theme_name="$2"
    local style_file="$theme_output_dir/waybar.css"

    log_verbose "Generating Waybar style for $theme_name"

    cat > "$style_file" << EOF
/* Waybar Theme: $theme_name */
/* Converted from Omarchy theme */
/* Generated on:
