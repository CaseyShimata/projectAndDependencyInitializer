#!/bin/bash
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

set -e

readonly SCRIPT_VERSION="1.0.0"

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/.functions.sh"

readonly FORMULA_PACKAGES=(
    "mas:Mac App Store CLI"
    "node:Node.js"
    "yarn:Yarn"
    "git-flow:Git Flow"
)

readonly CASK_PACKAGES=(
    "google-chrome:Google Chrome"
    "android-studio:Android Studio"
    "claude:Claude Desktop App"
    "claude-code:Claude Code CLI"
    "intellij-idea:IntelliJ IDEA Ultimate"
    "rectangle:Rectangle"
    "iterm2:iTerm2"
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

show_help() {
    cat << EOF
Development Environment Setup Script v$SCRIPT_VERSION

USAGE:
    $0 [options]

OPTIONS:
    help                    Show this help message
    upgrade    Upgrade existing packages

EXAMPLES:
    $0                     Fresh installation
    $0 upgrade Upgrade existing packages
EOF
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

    for package in "${FORMULA_PACKAGES[@]}"; do
        local name="${package%:*}" display="${package#*:}"
        install_tool "$name" "$display" "brew list '$name'" "brew install '$name' --quiet" "brew upgrade '$name' --quiet"
    done

    for package in "${CASK_PACKAGES[@]}"; do
        [ "$OS_TYPE" != "macos" ] && continue
        local name="${package%:*}" display="${package#*:}"
        install_tool "$name" "$display" "brew list --cask '$name'" "brew install --cask '$name' --quiet" "brew upgrade --cask '$name' --quiet"
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

install_xcode() {
    [ "$OS_TYPE" != "macos" ] && return
    progress "Installing Xcode for Expo development"
    
    if [ ! -d "/Library/Developer/CommandLineTools" ]; then
        info "Installing Command Line Tools via Software Update"
        /usr/bin/touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        PROD=$(/usr/sbin/softwareupdate -l | /usr/bin/grep "\*.*Command Line" | /usr/bin/tail -n 1 | /usr/bin/sed 's/^[^C]* //')
        if [ -n "$PROD" ]; then
            /usr/sbin/softwareupdate -i "$PROD" --verbose
            success "Command Line Tools installed"
        else
            warn "Command Line Tools not available via Software Update"
        fi
        /bin/rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    else
        success "Command Line Tools already installed"
    fi
    
    if [ ! -d "/Applications/Xcode.app" ]; then
        info "Installing Xcode from App Store (this may take a while...)"
        mas install 497799835 || warn "Failed to install Xcode - install manually from App Store"
    fi

    if [ -d "/Applications/Xcode.app" ] && command -v xcodebuild >/dev/null 2>&1; then
        if ! /usr/bin/xcodebuild -license check >/dev/null 2>&1; then
            info "Accepting Xcode license"
            /usr/bin/sudo /usr/bin/xcodebuild -license accept
        fi
        success "Xcode ready"
    else
        success "Using Command Line Tools only"
    fi
}

verify_installations() {
    local tools=(
        "brew:Homebrew" "zsh:Zsh" "node:Node.js" "yarn:Yarn" "git-flow:Git Flow" "expo:Expo CLI"
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

    info "Script Info:"
    success "  Version: $SCRIPT_VERSION"
    success "  Source: https://github.com/yourusername/dev-setup"
}

main() {
    case "${1:-}" in
        "help"|"-h"|"--help")
            show_help
            exit 0
            ;;
        "upgrade")
            UPGRADE_MODE=true
            info "Upgrade mode enabled"
            ;;
    esac

    msg "Development Environment Setup v$SCRIPT_VERSION" "$CYAN"
    info "This script runs non-interactively. Some operations may require manual follow-up."

    OS_TYPE=$(detect_os)
    ARCH=$(uname -m)
    if [ "$OS_TYPE" = "macos" ] && [ "$ARCH" = "arm64" ]; then
        ARCH="arm64"
    else
        ARCH="x86_64"
    fi

    info "OS: $OS_TYPE, Arch: $ARCH"

    check_root

    msg "Phase 1: Installing Homebrew and zsh" "$CYAN"
    install_homebrew
    install_zsh_via_brew "$@"

    msg "Phase 2: Configuring shell and installing packages" "$CYAN"
    install_oh_my_zsh
    install_packages
    install_xcode

    local elapsed=$(( $(/bin/date +%s 2>/dev/null || echo 0) - START_TIME ))
    msg "Setup Complete!" "$GREEN"
    printf '%sTotal time: %dm %ds%s\n' "$GREEN" $((elapsed/60)) $((elapsed%60)) "$NC"

    verify_installations
    
    info "Possible Next steps:"
        info "1. Set zsh as default shell: chsh -s $(command -v zsh)"
        info "2. Restart terminal for shell changes to take effect"
        info "3. Run 'claude auth' to configure Claude Code CLI"
        info "4. Configure Rectangle shortcuts in System Preferences"
}

main "$@"