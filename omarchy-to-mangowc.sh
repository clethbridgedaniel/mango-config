#!/usr/bin/env bash
# Omarchy to MangoWC Theme Converter v0.2
# Converts all Omarchy themes from ~/.config/omarchy/themes to MangoWC format
# Compatible with MangoWC (https://github.com/DreamMaoMao/mangowc)

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
Omarchy to MangoWC Bulk Theme Converter v2.0

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -s, --source DIR         Source directory containing Omarchy themes (default: ~/.config/omarchy/themes)
    -o, --output DIR         Output directory for MangoWC themes (default: ~/.config/mango/themes)
    -t, --themes THEME1,THEME2 Comma-separated list of specific themes to convert
    -v, --verbose            Enable verbose output
    -d, --dry-run            Show what would be converted without actually converting
    -i, --interactive        Interactive mode - select themes to convert
    -h, --help               Show this help message

EXAMPLES:
    # Convert all themes in default directory
    $0

    # Convert specific themes only
    $0 --themes "bauhaus,nagai-poolside"

    # Interactive mode with custom directories
    $0 --interactive --source ~/my-themes --output ~/mango-themes

    # Dry run to see what would be converted
    $0 --dry-run --verbose

DESCRIPTION:
    This script automatically discovers and converts all Omarchy themes to MangoWC format:
    - Scans ~/.config/omarchy/themes for theme directories
    - Converts each theme with palette.yml to MangoWC format
    - Generates configurations for MangoWC, Waybar, terminals, etc.
    - Creates installation scripts for each theme
    - Provides batch conversion with statistics

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
}

# Validate input directory and tools
validate_environment() {
    log_info "Validating environment..."

    # Check source directory
    if [[ ! -d "$OMARCHY_THEMES_DIR" ]]; then
        log_error "Omarchy themes directory does not exist: $OMARCHY_THEMES_DIR"
        log_info "Please ensure Omarchy is installed and themes are available"
        exit 1
    fi

    # Check for required tools
    local missing_tools=()
    for tool in yq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install missing tools:"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                yq)
                    log_info "  - yq: sudo pip install yq or sudo pacman -S go-yq"
                    ;;
            esac
        done
        exit 1
    fi

    log_success "Environment validation completed"
}

# Discover available themes
discover_themes() {
    log_info "Discovering Omarchy themes in: $OMARCHY_THEMES_DIR"
    
    local themes=()
    while IFS= read -r -d '' theme_dir; do
        local theme_name
        theme_name=$(basename "$theme_dir")
        local palette_file="$theme_dir/palette.yml"
        
        if [[ -f "$palette_file" ]]; then
            themes+=("$theme_name")
            log_verbose "Found valid theme: $theme_name"
        else
            log_verbose "Skipping directory without palette.yml: $theme_name"
        fi
    done < <(find "$OMARCHY_THEMES_DIR" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)

    if [[ ${#themes[@]} -eq 0 ]]; then
        log_warning "No valid themes found in $OMARCHY_THEMES_DIR"
        log_info "Make sure theme directories contain palette.yml files"
        exit 1
    fi

    log_success "Found ${#themes[@]} themes: ${themes[*]}"
    printf '%s\n' "${themes[@]}"
}

# Interactive theme selection
select_themes_interactive() {
    local available_themes=("$@")
    
    echo -e "\n${CYAN}Available Omarchy Themes:${NC}"
    for i in "${!available_themes[@]}"; do
        printf "  %d) %s\n" $((i+1)) "${available_themes[i]}"
    done
    
    echo -e "\n${CYAN}Selection Options:${NC}"
    echo "  - Enter numbers separated by spaces (e.g., 1 3 5)"
    echo "  - Enter 'all' to select all themes"
    echo "  - Enter 'none' to skip selection"
    
    while true; do
        read -p "Select themes to convert: " selection
        
        case "$selection" in
            all)
                SELECTED_THEMES=("${available_themes[@]}")
                break
                ;;
            none)
                SELECTED_THEMES=()
                break
                ;;
            *)
                # Parse numeric selection
                local selected=()
                local valid=true
                for num in $selection; do
                    if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le ${#available_themes[@]} ]]; then
                        selected+=("${available_themes[$((num-1))]}")
                    else
                        valid=false
                        break
                    fi
                done
                
                if [[ "$valid" == true ]] && [[ ${#selected[@]} -gt 0 ]]; then
                    SELECTED_THEMES=("${selected[@]}")
                    break
                else
                    log_warning "Invalid selection. Please try again."
                fi
                ;;
        esac
    done
    
    log_info "Selected themes: ${SELECTED_THEMES[*]}"
}

# Parse palette.yml and extract colors
parse_palette() {
    local theme_dir="$1"
    local palette_file="$theme_dir/palette.yml"
    
    log_verbose "Parsing palette file: $palette_file"

    # Declare associative arrays for color mapping
    declare -gA colors
    declare -gA ansi_colors
    declare -gA ansi_bright_colors
    declare -gA ansi_dim_colors

    # Parse main colors
    local main_colors
    main_colors=$(yq eval '. | to_entries | .[] | "\(.key)=\(.value)"' "$palette_file" 2>/dev/null || {
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
    if yq eval '.ansi_normal' "$palette_file" &>/dev/null; then
        local ansi_normal
        ansi_normal=$(yq eval '.ansi_normal | to_entries | .[] | "\(.key)=\(.value)"' "$palette_file")
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                ansi_colors["$key"]="$value"
                log_debug "Parsed ANSI color: $key = $value"
            fi
        done <<< "$ansi_normal"
    fi

    if yq eval '.ansi_bright' "$palette_file" &>/dev/null; then
        local ansi_bright
        ansi_bright=$(yq eval '.ansi_bright | to_entries | .[] | "\(.key)=\(.value)"' "$palette_file")
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                ansi_bright_colors["$key"]="$value"
                log_debug "Parsed ANSI bright color: $key = $value"
            fi
        done <<< "$ansi_bright"
    fi

    if yq eval '.ansi_dim' "$palette_file" &>/dev/null; then
        local ansi_dim
        ansi_dim=$(yq eval '.ansi_dim | to_entries | .[] | "\(.key)=\(.value)"' "$palette_file")
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                ansi_dim_colors["$key"]="$value"
                log_debug "Parsed ANSI dim color: $key = $value"
            fi
        done <<< "$ansi_dim"
    fi

    log_verbose "Palette parsing completed for $(basename "$theme_dir")"
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
/* Generated on: $(date) */

window {
    background-color: ${colors[secondary_bg]:-$161B22};
    color: ${colors[text_primary]:-$EAEFF5};
    border-radius: 0px;
    border: 1px solid ${colors[tertiary_bg]:-$222733};
}

#waybar {
    background-color: ${colors[secondary_bg]:-$161B22};
    color: ${colors[text_primary]:-$EAEFF5};
    border-bottom: 1px solid ${colors[tertiary_bg]:-$222733};
}

#workspaces button {
    padding: 0 5px;
    background-color: ${colors[tertiary_bg]:-$222733};
    color: ${colors[text_secondary]:-$C6CED8};
    border: 1px solid ${colors[tertiary_accent]:-$809D9E};
}

#workspaces button.active {
    background-color: ${colors[primary_accent]:-$E37B66};
    color: ${colors[primary_bg]:-$101318};
}

#workspaces button.urgent {
    background-color: ${colors[error]:-$CB886D};
    color: ${colors[text_primary]:-$EAEFF5};
}

#mode {
    background-color: ${colors[primary_accent]:-$E37B66};
    color: ${colors[primary_bg]:-$101318};
}

#clock, #battery, #cpu, #memory, #disk, #temperature, #backlight, #network, #pulseaudio, #custom-media, #tray, #mode, #idle_inhibitor, #scratchpad, #mpd {
    padding: 0 10px;
    margin: 0 5px;
    background-color: ${colors[tertiary_bg]:-$222733};
    color: ${colors[text_primary]:-$EAEFF5};
}

#clock {
    background-color: ${colors[tertiary_accent]:-$809D9E};
}

#battery.charging {
    color: ${colors[success]:-$789FA2};
}

#battery.warning:not(.charging) {
    color: ${colors[warning]:-$E7A46F};
}

#battery.critical:not(.charging) {
    color: ${colors[error]:-$CB886D};
}

EOF

    log_verbose "Waybar style generated: $style_file"
}

# Generate terminal configurations
generate_terminal_configs() {
    local theme_output_dir="$1"
    local theme_name="$2"
    local theme_source_dir="$2"
    
    log_verbose "Generating terminal configurations for $theme_name"

    # Generate Alacritty config
    if [[ -f "$theme_source_dir/alacritty.toml" ]]; then
        cp "$theme_source_dir/alacritty.toml" "$theme_output_dir/"
        log_verbose "Copied existing Alacritty configuration"
    else
        generate_alacritty_config "$theme_output_dir" "$theme_name"
    fi

    # Generate Kitty config
    if [[ -f "$theme_source_dir/kitty.conf" ]]; then
        cp "$theme_source_dir/kitty.conf" "$theme_output_dir/"
        log_verbose "Copied existing Kitty configuration"
    else
        generate_kitty_config "$theme_output_dir" "$theme_name"
    fi

    # Generate Ghostty config
    if [[ -f "$theme_source_dir/ghostty.conf" ]]; then
        cp "$theme_source_dir/ghostty.conf" "$theme_output_dir/"
        log_verbose "Copied existing Ghostty configuration"
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

# Generate Mako notification configuration
generate_mako_config() {
    local theme_output_dir="$1"
    local theme_name="$2"
    local config_file="$theme_output_dir/mako.conf"

    log_verbose "Generating Mako configuration for $theme_name"

    cat > "$config_file" << EOF
# Mako Theme: $theme_name
# Converted from Omarchy theme
# Generated on: $(date)

background-color=${colors[secondary_bg]:-$161B22}
text-color=${colors[text_primary]:-$EAEFF5}
border-color=${colors[primary_accent]:-$E37B66}
progress-color=${colors[primary_accent]:-$E37B66}

default-timeout=5000
border-size=2
padding=8
margin=8

[urgency=low]
background-color=${colors[tertiary_bg]:-$222733}
text-color=${colors[text_secondary]:-$C6CED8}

[urgency=high]
background-color=${colors[error]:-$CB886D}
text-color=${colors[text_primary]:-$EAEFF5}
border-color=${colors[warning]:-$E7A46F}

[urgency=critical]
background-color=${colors[error]:-$CB886D}
text-color=${colors[text_primary]:-$EAEFF5}
border-color=${colors[error]:-$CB886D}

EOF

    log_verbose "Mako configuration generated: $config_file"
}

# Generate SwayOSD configuration
generate_swayosd_config() {
    local theme_output_dir="$1"
    local theme_name="$2"
    local config_file="$theme_output_dir/swayosd.css"

    log_verbose "Generating SwayOSD configuration for $theme_name"

    cat > "$config_file" << EOF
/* SwayOSD Theme: $theme_name */
/* Converted from Omarchy theme */
/* Generated on: $(date) */

window {
    background-color: ${colors[secondary_bg]:-$161B22};
    border: 1px solid ${colors[primary_accent]:-$E37B66};
    border-radius: 8px;
    color: ${colors[text_primary]:-$EAEFF5};
}

.progressbar {
    background-color: ${colors[tertiary_bg]:-$222733};
    border: 1px solid ${colors[tertiary_accent]:-$809D9E};
    border-radius: 4px;
}

.progressbar-fill {
    background-color: ${colors[primary_accent]:-$E37B66};
    border-radius: 3px;
}

.label {
    color: ${colors[text_primary]:-$EAEFF5};
}

.value {
    color: ${colors[secondary_accent]:-$E0A568};
}

EOF

    log_verbose "SwayOSD configuration generated: $config_file"
}

# Generate installation script
generate_install_script() {
    local theme_output_dir="$1"
    local theme_name="$2"
    local install_script="$theme_output_dir/install.sh"

    log_verbose "Generating installation script for $theme_name"

    cat > "$install_script" << 'EOF'
#!/usr/bin/env bash
# Theme Installation Script
# Generated by Omarchy to MangoWC Theme Converter

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_NAME="$(basename "$SCRIPT_DIR")"
CONFIG_DIR="$HOME/.config/mango"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Install theme files
install_theme() {
    log_info "Installing MangoWC theme: $THEME_NAME"
    
    # Create mango config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR/themes"
    
    # Copy theme files
    cp -r "$SCRIPT_DIR" "$CONFIG_DIR/themes/"
    
    # Create symlink for active theme (optional)
    if [[ ! -L "$CONFIG_DIR/themes/current" ]]; then
        ln -sf "$CONFIG_DIR/themes/$THEME_NAME" "$CONFIG_DIR/themes/current"
        log_info "Created symlink: $CONFIG_DIR/themes/current -> $THEME_NAME"
    fi
    
    log_success "Theme installed successfully!"
    log_info "To activate the theme, add the following to your MangoWC config:"
    log_info "@include $CONFIG_DIR/themes/$THEME_NAME/config.conf"
}

# Backup existing configuration
backup_config() {
    local config_file="$CONFIG_DIR/config.conf"
    if [[ -f "$config_file" ]]; then
        local backup_file="$config_file.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$config_file" "$backup_file"
        log_info "Backed up existing configuration to: $backup_file"
    fi
}

# Main installation
main() {
    backup_config
    install_theme
    
    log_success "Installation completed!"
    log_info "Restart MangoWC to apply the theme changes."
}

main "$@"
EOF

    chmod +x "$install_script"
    log_verbose "Installation script generated: $install_script"
}

# Generate README file
generate_readme() {
    local theme_output_dir="$1"
    local theme_name="$2"
    local readme_file="$theme_output_dir/README.md"

    log_verbose "Generating README for $theme_name"

    cat > "$readme_file" << EOF
# $theme_name Theme for MangoWC

This theme was automatically converted from an Omarchy theme using the Omarchy to MangoWC Theme Converter.

## Theme Information

- **Name**: $theme_name
- **Generated**: $(date)
- **Source**: Omarchy theme system
- **Target**: MangoWC Wayland compositor

## Color Palette

| Color Name | Hex Code |
|------------|----------|
| Primary Background | ${colors[primary_bg]:-$101318} |
| Secondary Background | ${colors[secondary_bg]:-$161B22} |
| Tertiary Background | ${colors[tertiary_bg]:-$222733} |
| Primary Accent | ${colors[primary_accent]:-$E37B66} |
| Secondary Accent | ${colors[secondary_accent]:-$E0A568} |
| Tertiary Accent | ${colors[tertiary_accent]:-$809D9E} |
| Text Primary | ${colors[text_primary]:-$EAEFF5} |
| Text Secondary | ${colors[text_secondary]:-$C6CED8} |
| Text Dim | ${colors[text_dim]:-$98A0AE} |
| Success | ${colors[success]:-$789FA2} |
| Warning | ${colors[warning]:-$E7A46F} |
| Error | ${colors[error]:-$CB886D} |
| Info | ${colors[info]:-$8999AA} |
| Selection Background | ${colors[selection_bg]:-$2B3040} |

## Installation

1. Run the installation script:
   \`\`\`bash
   ./install.sh
   \`\`\`

2. Add the following to your MangoWC configuration file:
   \`\`\`
   @include ~/.config/mango/themes/$theme_name/config.conf
   \`\`\`

3. Restart MangoWC to apply the theme.

## Included Components

- **MangoWC Configuration** (\`config.conf\`)
- **Waybar Style** (\`waybar.css\`)
- **Terminal Configurations**:
  - Alacritty (\`alacritty.toml\`)
  - Kitty (\`kitty.conf\`)
  - Ghostty (\`ghostty.conf\`)
- **Notification Daemon** (\`mako.conf\`)
- **OSD Configuration** (\`swayosd.css\`)

## Customization

You can customize the theme by editing the generated configuration files. All colors are defined at the top of each file for easy modification.

## License

This theme maintains the same license as the original Omarchy theme.

EOF

    log_verbose "README file generated: $readme_file"
}

# Convert a single theme
convert_theme() {
    local theme_name="$1"
    local theme_source_dir="$OMARCHY_THEMES_DIR/$theme_name"
    local theme_output_dir="$OUTPUT_DIR/$theme_name"
    
    log_info "Converting theme: $theme_name"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would convert: $theme_source_dir -> $theme_output_dir"
        return 0
    fi

    # Create output directory
    mkdir -p "$theme_output_dir"
    
    # Parse palette
    if ! parse_palette "$theme_source_dir"; then
        log_error "Failed to parse palette for theme: $theme_name"
        return 1
    fi
    
    # Generate configuration files
    generate_mangowc_config "$theme_output_dir" "$theme_name"
    generate_waybar_style "$theme_output_dir" "$theme_name"
    generate_terminal_configs "$theme_output_dir" "$theme_name" "$theme_source_dir"
    generate_mako_config "$theme_output_dir" "$theme_name"
    generate_swayosd_config "$theme_output_dir" "$theme_name"
    
    # Generate documentation and installation script
    generate_install_script "$theme_output_dir" "$theme_name"
    generate_readme "$theme_output_dir" "$theme_name"
    
    log_success "Theme conversion completed: $theme_name"
    return 0
}

# Display conversion statistics
show_statistics() {
    echo -e "\n${CYAN}Conversion Summary:${NC}"
    echo "=================="
    
    local total=${#CONVERSION_STATS[@]}
    local successful=0
    local failed=0
    
    for result in "${CONVERSION_STATS[@]}"; do
        if [[ "$result" == "success" ]]; then
            ((successful++))
        else
            ((failed++))
        fi
    done
    
    echo -e "Total themes processed: ${BLUE}$total${NC}"
    echo -e "Successfully converted: ${GREEN}$successful${NC}"
    echo -e "Failed conversions: ${RED}$failed${NC}"
    
    if [[ "$successful" -gt 0 ]]; then
        echo -e "\n${GREEN}Successfully converted themes are available in:${NC}"
        echo -e "${BLUE}$OUTPUT_DIR${NC}"
    fi
}

# Main conversion function
convert_all_themes() {
    local themes_to_convert=("$@")
    
    if [[ ${#themes_to_convert[@]} -eq 0 ]]; then
        log_warning "No themes selected for conversion"
        return 0
    fi
    
    log_info "Starting bulk conversion of ${#themes_to_convert[@]} themes..."
    
    # Create output directory
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$OUTPUT_DIR"
    fi
    
    local total=${#themes_to_convert[@]}
    local current=0
    
    for theme_name in "${themes_to_convert[@]}"; do
        ((current++))
        echo -e "\n${CYAN}[$current/$total] Processing theme: $theme_name${NC}"
        
        if convert_theme "$theme_name"; then
            CONVERSION_STATS+=("success")
        else
            CONVERSION_STATS+=("failed")
        fi
    done
    
    show_statistics
}

# Main execution
main() {
    echo -e "${CYAN}Omarchy to MangoWC Bulk Theme Converter v2.0${NC}"
    echo -e "${CYAN}=============================================${NC}"
    
    parse_args "$@"
    validate_environment
    
    # Discover available themes
    local available_themes
    readarray -t available_themes < <(discover_themes)
    
    # Determine which themes to convert
    if [[ "$INTERACTIVE" == true ]]; then
        select_themes_interactive "${available_themes[@]}"
    elif [[ ${#SELECTED_THEMES[@]} -gt 0 ]]; then
        # Validate selected themes
        local validated_themes=()
        for theme in "${SELECTED_THEMES[@]}"; do
            if [[ " ${available_themes[*]} " =~ " $theme " ]]; then
                validated_themes+=("$theme")
            else
                log_warning "Theme not found, skipping: $theme"
            fi
        done
        SELECTED_THEMES=("${validated_themes[@]}")
    else
        SELECTED_THEMES=("${available_themes[@]}")
    fi
    
    # Show what will be converted
    if [[ ${#SELECTED_THEMES[@]} -gt 0 ]]; then
        echo -e "\n${CYAN}Themes to convert:${NC}"
        for theme in "${SELECTED_THEMES[@]}"; do
            echo "  - $theme"
        done
    else
        log_warning "No themes selected for conversion"
        exit 0
    fi
    
    # Perform conversion
    convert_all_themes "${SELECTED_THEMES[@]}"
    
    if [[ "$DRY_RUN" == false ]]; then
        echo -e "\n${GREEN}Bulk conversion completed!${NC}"
        log_info "Converted themes are available in: $OUTPUT_DIR"
        log_info "Run './install.sh' in each theme directory to install them."
    else
        echo -e "\n${YELLOW}Dry run completed. No files were modified.${NC}"
    fi
}

# Execute main function with all arguments
main "$@"
