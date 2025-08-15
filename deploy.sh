#!/bin/bash
# Ensure PATH includes system directories - this runs in both bash and zsh
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

set -e

readonly RED=$'\033[0;31m' GREEN=$'\033[0;32m' YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m' CYAN=$'\033[0;36m' NC=$'\033[0m'

readonly CASK_PACKAGES=(
    "google-chrome:Google Chrome"
    "android-studio:Android Studio"
    "claude:Claude Desktop App"
    "claude-code:Claude Code CLI"
    "intellij-idea:IntelliJ IDEA Ultimate"
    "rectangle:Rectangle"
    "iterm2:iTerm2"
)

readonly FORMULA_PACKAGES=(
    "node:Node.js"
    "yarn:Yarn"
)

readonly NPM_PACKAGES=(
    "expo-cli:expo:Expo CLI"
)

CURRENT_STEP=0
START_TIME=$(/bin/date +%s 2>/dev/null || echo 0)
TOTAL_STEPS=$((4 + ${#CASK_PACKAGES[@]} + ${#FORMULA_PACKAGES[@]} + ${#NPM_PACKAGES[@]}))
UPGRADE_MODE=false
OS_TYPE=""
ARCH=""

msg() { printf '%s%s%s\n' "${2:-$GREEN}" "$1" "$NC"; }
progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local elapsed=$(( $(/bin/date +%s 2>/dev/null || echo 0) - START_TIME ))
    printf '%s[%d/%d] [%02d:%02d] %s%s\n' "$BLUE" "$CURRENT_STEP" "$TOTAL_STEPS" $((elapsed/60)) $((elapsed%60)) "$1" "$NC"
}
error() { msg "✗ $1" "$RED"; exit 1; }
success() { msg "✓ $1"; }
warn() { msg "⚠ $1" "$YELLOW"; }
info() { msg "→ $1" "$CYAN"; }

detect_os() {
    case "$(uname)" in
        "Darwin") echo "macos" ;;
        "Linux") echo "linux" ;;
        *) error "Unsupported OS: $(uname)" ;;
    esac
}

check_root() {
    local uid
    uid="${EUID:-$(id -u)}"
    if [ "$uid" = "0" ]; then
        error "DO NOT run with sudo! Run as regular user."
    fi
}

run_cmd() {
    if eval "$1" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

add_to_shell_config() {
    local line="$1"
    /bin/echo "$line" >> "$HOME/.bashrc"
    [ -f "$HOME/.zshrc" ] && /bin/echo "$line" >> "$HOME/.zshrc"
}

install_homebrew() {
    progress "Installing/Checking Homebrew"
    
    local brew_paths=("/opt/homebrew/bin/brew" "/usr/local/bin/brew" "/home/linuxbrew/.linuxbrew/bin/brew")
    local brew_found=""
    
    for path in "${brew_paths[@]}" "$(command -v brew 2>/dev/null)"; do
        if [ -n "$path" ] && [ -x "$path" ]; then
            brew_found="$path"
            break
        fi
    done
    
    if [ -n "$brew_found" ]; then
        success "Homebrew found at $brew_found"
        command -v brew >/dev/null || eval "$("$brew_found" shellenv)"
    else
        info "Installing Homebrew"
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        local brew_path
        case "$OS_TYPE" in
            "macos") brew_path=$( [ "$ARCH" = "arm64" ] && echo "/opt/homebrew/bin/brew" || echo "/usr/local/bin/brew" ) ;;
            *) brew_path="/home/linuxbrew/.linuxbrew/bin/brew" ;;
        esac
        
        add_to_shell_config "eval \"\$($brew_path shellenv)\""
        eval "$("$brew_path" shellenv)"
        success "Homebrew installed"
    fi
}

install_zsh_via_brew() {
    progress "Installing zsh via Homebrew"
    
    if ! command -v zsh >/dev/null; then
        info "Installing zsh"
        brew install zsh
        success "zsh installed"
    else
        success "zsh already available"
    fi
    
    if [ -z "$ZSH_VERSION" ]; then
        info "Restarting script in zsh"
        exec env PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH" /bin/zsh "$0" "$@"
    fi
    
    success "Running in zsh"
}

install_oh_my_zsh() {
    progress "Installing/Configuring Oh-My-Zsh"
    
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        info "Installing Oh-My-Zsh"
        RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" 2>/dev/null
        success "Oh-My-Zsh installed"
    else
        success "Oh-My-Zsh already installed"
    fi
    
    # Check if zsh is the default shell
    local zsh_path
    zsh_path="$(command -v zsh)"
    if [ "$SHELL" != "$zsh_path" ]; then
        warn "Zsh is not your default shell. To change it, run: chsh -s $zsh_path"
    fi
    
    local zshrc="$HOME/.zshrc"
    if [ -f "$zshrc" ]; then
        if /usr/bin/grep -q 'ZSH_THEME="robbyrussell"' "$zshrc"; then
            info "Setting theme to agnoster"
            /usr/bin/sed -i.bak 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' "$zshrc"
        fi
        
        if ! /usr/bin/grep -q "plugins.*git.*brew" "$zshrc"; then
            info "Adding useful plugins"
            local plugins="plugins=(git brew node npm yarn"
            [ "$OS_TYPE" = "macos" ] && plugins="$plugins macos"
            plugins="$plugins)"
            /usr/bin/sed -i.bak "s/plugins=(git)/$plugins/" "$zshrc"
        fi
    fi
    
    success "Oh-My-Zsh configured"
}

install_tool() {
    local name="$1" display="$2" check_cmd="$3" install_cmd="$4" upgrade_cmd="$5"

    progress "Installing/Checking $display"

    if run_cmd "$check_cmd"; then
        success "$display already installed"
        if [ "$UPGRADE_MODE" = true ] && [ -n "$upgrade_cmd" ]; then
            info "Upgrading $display"
            if run_cmd "$upgrade_cmd"; then
                success "$display upgraded"
            else
                info "$display already up to date"
            fi
        fi
    else
        info "Installing $display"
        if run_cmd "$install_cmd"; then
            success "$display installed"
        else
            warn "Failed to install $display"
        fi
    fi
}

install_packages() {
    if [ "$UPGRADE_MODE" = true ]; then
        info "Updating Homebrew"
        brew update --quiet && brew upgrade --quiet
    fi
    
    for package in "${CASK_PACKAGES[@]}"; do
        [ "$OS_TYPE" != "macos" ] && continue
        local name="${package%:*}" display="${package#*:}"
        install_tool "$name" "$display" "brew list --cask '$name'" "brew install --cask '$name' --quiet" "brew upgrade --cask '$name' --quiet"
    done

    for package in "${FORMULA_PACKAGES[@]}"; do
        local name="${package%:*}" display="${package#*:}"
        install_tool "$name" "$display" "brew list '$name'" "brew install '$name' --quiet" "brew upgrade '$name' --quiet"
    done

    for package in "${NPM_PACKAGES[@]}"; do
        local name="${package%%:*}" cmd="${package#*:}" display="${package##*:}"
        cmd="${cmd%:*}"

        if [ ! -w "$(npm config get prefix 2>/dev/null)" ]; then
            info "Setting up NPM global directory"
            /bin/mkdir -p "$HOME/.npm-global"
            npm config set prefix "$HOME/.npm-global"
            add_to_shell_config "export PATH=\"\$HOME/.npm-global/bin:\$PATH\""
            export PATH="$HOME/.npm-global/bin:$PATH"
        fi

        install_tool "$cmd" "$display" "command -v '$cmd'" "npm install -g '$name' --silent" "npm update -g '$name' --silent"
    done
}

install_xcode_tools() {
    # Only run on macOS - Linux doesn't have/need Xcode
    [ "$OS_TYPE" != "macos" ] && return

    progress "Installing/Checking Xcode Command Line Tools"

    # Check if already installed - multiple methods
    if xcode-select -p >/dev/null 2>&1; then
        success "Xcode Command Line Tools already installed at $(xcode-select -p)"
        return
    fi
    
    # Double-check with pkgutil
    if /usr/sbin/pkgutil --pkg-info=com.apple.pkg.CLTools_Executables >/dev/null 2>&1; then
        success "Xcode Command Line Tools already installed (verified via pkgutil)"
        return
    fi

    info "Attempting to install Xcode Command Line Tools"
    
    # Method 1: Try the touchfile method for automated installation
    # This sometimes works without sudo on newer macOS versions
    /usr/bin/touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress 2>/dev/null || true
    
    # Find the Command Line Tools package
    info "Checking for available Xcode Command Line Tools updates..."
    local prod
    prod="$(softwareupdate --list 2>&1 | /usr/bin/grep "\*.*Command Line Tools" | /usr/bin/tail -1 | /usr/bin/awk -F'[*] ' '{print $2}')"
    
    if [ -n "$prod" ]; then
        info "Found package: $prod"
        # Try to install without sudo first (might work on some systems)
        if softwareupdate --install "$prod" --agree-to-license 2>/dev/null; then
            success "Xcode Command Line Tools installed"
        else
            # If that fails, try triggering the GUI installer
            info "Automated installation requires sudo. Triggering GUI installer instead..."
            xcode-select --install 2>/dev/null || true
            warn "Xcode Command Line Tools installation dialog triggered"
            warn "Please complete the installation in the popup window"
            warn "Or run manually with sudo: softwareupdate --install '$prod' --agree-to-license"
        fi
    else
        # Fallback: trigger the GUI installer
        info "Could not find Command Line Tools in software updates. Triggering GUI installer..."
        if xcode-select --install 2>/dev/null; then
            warn "Xcode Command Line Tools installation dialog should appear"
            warn "Please complete the installation in the popup window"
        else
            warn "Could not trigger installer. You may need to:"
            warn "1. Download from: https://developer.apple.com/xcode/resources/"
            warn "2. Or install full Xcode from the App Store"
        fi
    fi
    
    /bin/rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress 2>/dev/null || true
}

verify_installations() {
    local tools=(
        "brew:Homebrew" "zsh:Zsh" "node:Node.js" "yarn:Yarn" "expo:Expo CLI"
    )

    info "Verification Summary:"
    for tool in "${tools[@]}"; do
        local cmd="${tool%:*}" name="${tool#*:}"
        if command -v "$cmd" >/dev/null; then
            local version=""
            case "$cmd" in
                "brew") version=" $(brew --version | /usr/bin/head -1)" ;;
                "node"|"yarn") version=" $(${cmd} --version 2>/dev/null)" ;;
            esac
            success "  $name$version"
        else
            warn "  $name not found"
        fi
    done

    if [ "$OS_TYPE" = "macos" ]; then
        local apps=("Google Chrome" "Android Studio" "Claude" "IntelliJ IDEA" "Rectangle" "iTerm")
        for app in "${apps[@]}"; do
            if /bin/ls "/Applications/$app"* >/dev/null 2>&1; then
                success "  $app"
            else
                warn "  $app not found"
            fi
        done
    fi
}

main() {
    msg "=== Development Environment Setup ===" "$CYAN"
    info "This script runs non-interactively. Some operations may require manual follow-up."

    OS_TYPE=$(detect_os)
    ARCH=$(uname -m)
    if [ "$OS_TYPE" = "macos" ] && [ "$ARCH" = "arm64" ]; then
        ARCH="arm64"
    else
        ARCH="x86_64"
    fi

    info "OS: $OS_TYPE, Arch: $ARCH"

    if [ "$1" = "upgrade dependencies" ]; then
        UPGRADE_MODE=true
        info "Upgrade mode enabled"
    fi

    check_root

    msg "Phase 1: Installing Homebrew and zsh" "$CYAN"
    install_homebrew
    install_zsh_via_brew "$@"

    msg "Phase 2: Configuring shell and installing packages" "$CYAN"
    install_oh_my_zsh
    install_packages
    install_xcode_tools

    local elapsed=$(( $(/bin/date +%s 2>/dev/null || echo 0) - START_TIME ))
    msg "=== Setup Complete! ===" "$GREEN"
    printf '%sTotal time: %dm %ds%s\n' "$GREEN" $((elapsed/60)) $((elapsed%60)) "$NC"

    verify_installations
    
    info "Next steps:"
    if [ "$SHELL" != "$(command -v zsh)" ]; then
        info "1. Set zsh as default shell: chsh -s $(command -v zsh)"
        info "2. Restart terminal for shell changes to take effect"
        info "3. Run 'claude auth' to configure Claude Code CLI"
        info "4. Configure Rectangle shortcuts in System Preferences"
    else
        info "1. Run 'claude auth' to configure Claude Code CLI"
        info "2. Configure Rectangle shortcuts in System Preferences"
    fi
}

main "$@"
