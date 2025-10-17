#!/usr/bin/env bash
# Omarchy to MangoWC Theme Converter v1.0
# Converts Omarchy themes (eg https://github.com/somerocketeer/omarchy-bauhaus-theme) to MangoWC format
# Compatible with MangoWC (https://github.com/DreamMaoMao/mangowc)

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_NAME=""
OUTPUT_DIR=""
THEME_SOURCE_DIR=""
VERBOSE=false

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

# Display help information
show_help() {
    cat << EOF
Omarchy to MangoWC Theme Converter

USAGE:
    $0 [OPTIONS] <theme_source_directory> <output_directory>

ARGUMENTS:
    theme_source_directory    Path to the Omarchy theme directory containing palette.yml
    output_directory          Directory where converted MangoWC theme will be saved

OPTIONS:
    -n, --name NAME          Name for the converted theme (default: derived from source directory)
    -v, --verbose            Enable verbose output
    -h, --help               Show this help message

EXAMPLE:
    $0 --name "bauhaus-mango" ./omarchy-bauhaus-theme ~/.config/mango/themes

DESCRIPTION:
    This script converts Omarchy themes to MangoWC format by:
    - Parsing palette.yml for color definitions
    - Mapping colors to MangoWC configuration format
    - Generating compatible theme files
    - Creating necessary directory structure

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                THEME_NAME="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
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
                if [[ -z "$THEME_SOURCE_DIR" ]]; then
                    THEME_SOURCE_DIR="$1"
                elif [[ -z "$OUTPUT_DIR" ]]; then
                    OUTPUT_DIR="$1"
                else
                    log_error "Too many arguments"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$THEME_SOURCE_DIR" || -z "$OUTPUT_DIR" ]]; then
        log_error "Missing required arguments"
        show_help
        exit 1
    fi

    # Set default theme name if not provided
    if [[ -z "$THEME_NAME" ]]; then
        THEME_NAME=$(basename "$THEME_SOURCE_DIR" | sed 's/omarchy-//g' | sed 's/-theme//g')
    fi

    log_verbose "Theme source directory: $THEME_SOURCE_DIR"
    log_verbose "Output directory: $OUTPUT_DIR"
    log_verbose "Theme name: $THEME_NAME"
}

# Validate input directory and files
validate_input() {
    log_info "Validating input directory and files..."

    if [[ ! -d "$THEME_SOURCE_DIR" ]]; then
        log_error "Theme source directory does not exist: $THEME_SOURCE_DIR"
        exit 1
    fi

    local palette_file="$THEME_SOURCE_DIR/palette.yml"
    if [[ ! -f "$palette_file" ]]; then
        log_error "palette.yml not found in theme source directory: $palette_file"
        exit 1
    fi

    # Check for required tools
    for tool in yq; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            log_info "Please install yq (https://github.com/mikefarah/yq) to parse YAML files"
            exit 1
        fi
    done

    log_success "Input validation completed"
}

# Create output directory structure
create_output_structure() {
    log_info "Creating output directory structure..."

    mkdir -p "$OUTPUT_DIR"
    local theme_output_dir="$OUTPUT_DIR/$THEME_NAME"
    mkdir -p "$theme_output_dir"

    log_verbose "Created theme output directory: $theme_output_dir"
    echo "$theme_output_dir"
}

# Parse palette.yml and extract colors
parse_palette() {
    local palette_file="$THEME_SOURCE_DIR/palette.yml"
    log_info "Parsing palette file: $palette_file"

    # Declare associative arrays for color mapping
    declare -gA colors
    declare -gA ansi_colors
    declare -gA ansi_bright_colors
    declare -gA ansi_dim_colors

    # Parse main colors
    local main_colors
    main_colors=$(yq eval '. | to_entries | .[] | "\(.key)=\(.value)"' "$palette_file" 2>/dev/null || {
        log_error "Failed to parse palette.yml"
        exit 1
    })

    while IFS='=' read -r key value; do
        if [[ -n "$key" && -n "$value" ]]; then
            colors["$key"]="$value"
            log_verbose "Parsed color: $key = $value"
        fi
    done <<< "$main_colors"

    # Parse ANSI colors if they exist
    if yq eval '.ansi_normal' "$palette_file" &>/dev/null; then
        local ansi_normal
        ansi_normal=$(yq eval '.ansi_normal | to_entries | .[] | "\(.key)=\(.value)"' "$palette_file")
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                ansi_colors["$key"]="$value"
                log_verbose "Parsed ANSI color: $key = $value"
            fi
        done <<< "$ansi_normal"
    fi

    if yq eval '.ansi_bright' "$palette_file" &>/dev/null; then
        local ansi_bright
        ansi_bright=$(yq eval '.ansi_bright | to_entries | .[] | "\(.key)=\(.value)"' "$palette_file")
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                ansi_bright_colors["$key"]="$value"
                log_verbose "Parsed ANSI bright color: $key = $value"
            fi
        done <<< "$ansi_bright"
    fi

    if yq eval '.ansi_dim' "$palette_file" &>/dev/null; then
        local ansi_dim
        ansi_dim=$(yq eval '.ansi_dim | to_entries | .[] | "\(.key)=\(.value)"' "$palette_file")
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                ansi_dim_colors["$key"]="$value"
                log_verbose "Parsed ANSI dim color: $key = $value"
            fi
        done <<< "$ansi_dim"
    fi

    log_success "Palette parsing completed"
}

# Generate MangoWC configuration file
generate_mangowc_config() {
    local theme_output_dir="$1"
    local config_file="$theme_output_dir/config.conf"

    log_info "Generating MangoWC configuration..."

    cat > "$config_file" << EOF
# MangoWC Theme: $THEME_NAME
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

    log_success "MangoWC configuration generated: $config_file"
}

# Generate Waybar style configuration
generate_waybar_style() {
    local theme_output_dir="$1"
    local style_file="$theme_output_dir/waybar.css"

    log_info "Generating Waybar style configuration..."

    cat > "$style_file" << EOF
/* Waybar Theme: $THEME_NAME */
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

    log_success "Waybar style generated: $style_file"
}

# Generate terminal configuration
generate_terminal_config() {
    local theme_output_dir="$1"
    
    log_info "Generating terminal configurations..."

    # Generate Alacritty config
    if [[ -f "$THEME_SOURCE_DIR/alacritty.toml" ]]; then
        cp "$THEME_SOURCE_DIR/alacritty.toml" "$theme_output_dir/"
        log_verbose "Copied existing Alacritty configuration"
    else
        generate_alacritty_config "$theme_output_dir"
    fi

    # Generate Kitty config
    if [[ -f "$THEME_SOURCE_DIR/kitty.conf" ]]; then
        cp "$THEME_SOURCE_DIR/kitty.conf" "$theme_output_dir/"
        log_verbose "Copied existing Kitty configuration"
    else
        generate_kitty_config "$theme_output_dir"
    fi

    # Generate Ghostty config
    if [[ -f "$THEME_SOURCE_DIR/ghostty.conf" ]]; then
        cp "$THEME_SOURCE_DIR/ghostty.conf" "$theme_output_dir/"
        log_verbose "Copied existing Ghostty configuration"
    fi
}

# Generate Alacritty configuration
generate_alacritty_config() {
    local theme_output_dir="$1"
    local config_file="$theme_output_dir/alacritty.toml"

    cat > "$config_file" << EOF
# Alacritty Theme: $THEME_NAME
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

    log_success "Alacritty configuration generated: $config_file"
}

# Generate Kitty configuration
generate_kitty_config() {
    local theme_output_dir="$1"
    local config_file="$theme_output_dir/kitty.conf"

    cat > "$config_file" << EOF
# Kitty Theme: $THEME_NAME
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

    log_success "Kitty configuration generated: $config_file"
}

# Generate Mako notification configuration
generate_mako_config() {
    local theme_output_dir="$1"
    local config_file="$theme_output_dir/mako.conf"

    log_info "Generating Mako notification configuration..."

    cat > "$config_file" << EOF
# Mako Theme: $THEME_NAME
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

    log_success "Mako configuration generated: $config_file"
}

# Generate SwayOSD configuration
generate_swayosd_config() {
    local theme_output_dir="$1"
    local config_file="$theme_output_dir/swayosd.css"

    log_info "Generating SwayOSD configuration..."

    cat > "$config_file" << EOF
/* SwayOSD Theme: $THEME_NAME */
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

    log_success "SwayOSD configuration generated: $config_file"
}

# Generate installation script
generate_install_script() {
    local theme_output_dir="$1"
    local install_script="$theme_output_dir/install.sh"

    log_info "Generating installation script..."

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
    log_success "Installation script generated: $install_script"
}

# Generate README file
generate_readme() {
    local theme_output_dir="$1"
    local readme_file="$theme_output_dir/README.md"

    log_info "Generating README file..."

    cat > "$readme_file" << EOF
# $THEME_NAME Theme for MangoWC

This theme was automatically converted from an Omarchy theme using the Omarchy to MangoWC Theme Converter.

## Theme Information

- **Name**: $THEME_NAME
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
   @include ~/.config/mango/themes/$THEME_NAME/config.conf
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

    log_success "README file generated: $readme_file"
}

# Main conversion function
convert_theme() {
    log_info "Starting theme conversion process..."
    
    # Create output structure
    local theme_output_dir
    theme_output_dir=$(create_output_structure)
    
    # Parse palette
    parse_palette
    
    # Generate configuration files
    generate_mangowc_config "$theme_output_dir"
    generate_waybar_style "$theme_output_dir"
    generate_terminal_config "$theme_output_dir"
    generate_mako_config "$theme_output_dir"
    generate_swayosd_config "$theme_output_dir"
    
    # Generate documentation and installation script
    generate_install_script "$theme_output_dir"
    generate_readme "$theme_output_dir"
    
    log_success "Theme conversion completed successfully!"
    log_info "Converted theme location: $theme_output_dir"
    log_info "Run './install.sh' in the theme directory to install the theme."
}

# Main execution
main() {
    log_info "Omarchy to MangoWC Theme Converter v1.0"
    log_info "========================================="
    
    parse_args "$@"
    validate_input
    convert_theme
}

# Execute main function with all arguments
main "$@"
