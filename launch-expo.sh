#!/bin/bash
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"
set -eE

readonly SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly CYAN=$'\033[0;36m'
readonly NC=$'\033[0m'

msg() { printf '%s%s%s\n' "${2:-$GREEN}" "$1" "$NC"; }
error() { msg "ERROR: $1" "$RED"; exit 1; }
success() { msg "$1"; }
warn() { msg "$1" "$YELLOW"; }
info() { msg "$1" "$CYAN"; }

trap 'error "Command failed at line $LINENO: $BASH_COMMAND"' ERR

readonly FORMULA_PACKAGES=(
    "mas:Mac App Store CLI"
    "node:Node.js"
    "yarn:Yarn"
    "git:Git"
    "git-flow:Git Flow"
    "gh:GitHub CLI"
    "git-crypt:Git Crypt"
    "gnupg:GnuPG"
    "tmux:Terminal Multiplexer"
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
UPGRADE_MODE="${1:-1}"
PROJECT_SELECTION="${2:-}"
OS_TYPE=""
ARCH=""

progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local elapsed=$(( $(/bin/date +%s 2>/dev/null || echo 0) - START_TIME ))
    printf '%s[%d/%d] [%02d:%02d] %s%s\n' "$BLUE" "$CURRENT_STEP" "$TOTAL_STEPS" $((elapsed/60)) $((elapsed%60)) "$1" "$NC"
}

detect_os() {
    case "$(uname)" in
        "Darwin") echo "macos" ;;
        "Linux") echo "linux" ;;
        *) error "Unsupported OS: $(uname)" ;;
    esac
}

check_root() {
    if [ "${EUID:-$(id -u)}" = "0" ]; then
        error "DO NOT run with sudo! Run as regular user."
    fi
}

add_to_shell_config() {
    local line="$1"
    echo "$line" >> "$HOME/.bashrc" 2>/dev/null || true
    [ -f "$HOME/.zshrc" ] && echo "$line" >> "$HOME/.zshrc" 2>/dev/null || true
}

decrypt_env_if_needed() {
    info "Checking for encrypted .env file"
    
    if [ -f "$SCRIPT_DIR/.env" ] && file "$SCRIPT_DIR/.env" | /usr/bin/grep -q "ASCII text"; then
        success ".env file already decrypted"
        return 0
    fi

    info "Attempting to unlock git-crypt protected files"
    cd "$SCRIPT_DIR"
    if git-crypt unlock 2>/dev/null; then
        success "Repository unlocked with git-crypt"
        cd - >/dev/null
        return 0
    else
        warn "Git-crypt unlock failed. run:"
        warn "gpg --full-generate-key"
        warn "get <YOUR_KEY_ID> from 'gpg --list-secret-keys --keyid-format=long'"
        warn "gpg --send-keys --keyserver hkps://keys.openpgp.org <YOUR_KEY_ID>"
        warn "then have the admin run:"
        warn "gpg --keyserver hkps://keys.openpgp.org --search-keys <THEIR_EMAIL>"
        warn "git-crypt add-gpg-user <THEIR_KEY_ID>"
        cd - >/dev/null
        # Continue anyway as .env might not be encrypted
        if [ ! -f "$SCRIPT_DIR/.env" ]; then
            error "No .env file found and git-crypt failed"
        fi
    fi
}

install_homebrew() {
    progress "Setting up Homebrew package manager"

    local brew_found=""
    for path in "/opt/homebrew/bin/brew" "/usr/local/bin/brew" "/home/linuxbrew/.linuxbrew/bin/brew"; do
        if [ -x "$path" ]; then
            brew_found="$path"
            break
        fi
    done

    if [ -n "$brew_found" ]; then
        success "Homebrew found at $brew_found"
        eval "$("$brew_found" shellenv)" || error "Failed to setup Homebrew environment"
        return 0
    fi

    info "Installing Homebrew - this will download and install the package manager"
    if ! NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        error "Failed to install Homebrew"
    fi

    local brew_path
    case "$OS_TYPE" in
        "macos") 
            if [ "$ARCH" = "arm64" ]; then
                brew_path="/opt/homebrew/bin/brew"
            else
                brew_path="/usr/local/bin/brew"
            fi
            ;;
        *) brew_path="/home/linuxbrew/.linuxbrew/bin/brew" ;;
    esac

    if [ ! -x "$brew_path" ]; then
        error "Homebrew installation failed - brew not found at $brew_path"
    fi

    add_to_shell_config "eval \"\$($brew_path shellenv)\""
    eval "$("$brew_path" shellenv)" || error "Failed to setup Homebrew environment"
    success "Homebrew installed and configured"
}

install_zsh_via_brew() {
    progress "Ensuring zsh shell is available"

    if ! command -v zsh >/dev/null 2>&1; then
        info "Installing zsh shell"
        if ! brew install zsh; then
            error "Failed to install zsh"
        fi
    else
        success "zsh shell is available"
    fi

    if [ -z "$ZSH_VERSION" ]; then
        info "Switching to zsh for enhanced shell features"
        exec env PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH" /bin/zsh "$0" "$@"
    fi

    success "Running in zsh environment"
}

install_oh_my_zsh() {
    progress "Setting up Oh-My-Zsh framework"

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        info "Installing Oh-My-Zsh for better shell experience"
        if ! RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" 2>/dev/null; then
            warn "Oh-My-Zsh installation had issues but continuing"
        fi
    else
        success "Oh-My-Zsh framework already installed"
    fi

    local zshrc="$HOME/.zshrc"
    if [ -f "$zshrc" ]; then
        info "Configuring zsh theme and plugins"
        sed -i.bak 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' "$zshrc" 2>/dev/null || true
        
        local plugins="plugins=(git brew node npm yarn"
        [ "$OS_TYPE" = "macos" ] && plugins="$plugins macos"
        plugins="$plugins)"
        sed -i.bak "s/plugins=(git)/$plugins/" "$zshrc" 2>/dev/null || true
    fi
    
    success "Shell environment configured"
}

install_packages() {
    info "Installing required development tools"
    
    if [ "$UPGRADE_MODE" = "2" ]; then
        info "Updating Homebrew package definitions"
        brew update --quiet || warn "Could not update Homebrew"
    fi

    for package in "${FORMULA_PACKAGES[@]}"; do
        local name="${package%:*}" 
        local display="${package#*:}"
        progress "Checking $display"
        if brew list "$name" >/dev/null 2>&1; then
            if [ "$UPGRADE_MODE" = "2" ]; then
                info "Upgrading $display to latest version"
                brew upgrade "$name" --quiet 2>/dev/null || true
            else
                success "$display is installed"
            fi
        else
            info "Installing $display"
            if brew install "$name" --quiet; then
                success "$display installed successfully"
            else
                warn "Failed to install $display - may need manual installation"
            fi
        fi
    done

    if [ "$OS_TYPE" = "macos" ]; then
        info "Installing macOS desktop applications"
        for package in "${CASK_PACKAGES[@]}"; do
            local name="${package%:*}"
            local display="${package#*:}"
            progress "Checking $display"
            if brew list --cask "$name" >/dev/null 2>&1; then
                if [ "$UPGRADE_MODE" = "2" ]; then
                    info "Upgrading $display application"
                    brew upgrade --cask "$name" --quiet 2>/dev/null || true
                else
                    success "$display is installed"
                fi
            else
                info "Installing $display application"
                if brew install --cask "$name" --quiet; then
                    success "$display installed successfully"
                else
                    warn "Failed to install $display - may need manual installation"
                fi
            fi
        done
    fi

    info "Configuring Yarn global package directory"
    yarn config set prefix "$HOME/.yarn-global" 2>/dev/null || warn "Could not set yarn prefix"
    add_to_shell_config "export PATH=\"\$HOME/.yarn-global/bin:\$PATH\""
    export PATH="$HOME/.yarn-global/bin:$PATH"

    for package in "${NPM_PACKAGES[@]}"; do
        local name="${package%%:*}"
        local cmd="${package#*:}"
        cmd="${cmd%:*}"
        local display="${package##*:}"
        progress "Checking $display"
        
        if command -v "$cmd" >/dev/null 2>&1; then
            if [ "$UPGRADE_MODE" = "2" ]; then
                info "Upgrading $display to latest version"
                yarn global upgrade "$name" 2>/dev/null || true
            else
                success "$display is installed"
            fi
        else
            info "Installing $display globally"
            if yarn global add "$name"; then
                success "$display installed successfully"
            else
                warn "Failed to install $display - may need manual installation"
            fi
        fi
    done
}

install_xcode() {
    [ "$OS_TYPE" != "macos" ] && return
    progress "Setting up Xcode for iOS development"
    
    if [ ! -d "/Library/Developer/CommandLineTools" ]; then
        info "Installing Xcode Command Line Tools for compilation support"
        touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        PROD=$(softwareupdate -l | /usr/bin/grep "\*.*Command Line" | tail -n 1 | sed 's/^[^C]* //')
        if [ -n "$PROD" ]; then
            softwareupdate -i "$PROD" --verbose || warn "Failed to install Command Line Tools"
        fi
        rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    else
        success "Xcode Command Line Tools already installed"
    fi
    
    if [ ! -d "/Applications/Xcode.app" ]; then
        info "Installing Xcode from App Store (this is a large download)"
        mas install 497799835 || warn "Failed to install Xcode - install manually from App Store"
    else
        success "Xcode application found"
    fi

    if [ -d "/Applications/Xcode.app" ]; then
        # Check if Xcode is already configured
        if xcode-select -p 2>/dev/null | /usr/bin/grep -q "/Applications/Xcode.app/Contents/Developer"; then
            success "Xcode developer tools already configured"
        else
            info "Configuring Xcode developer tools (may require admin password)"
            if sudo -n true 2>/dev/null; then
                # Can use sudo without password
                sudo xcode-select --switch "/Applications/Xcode.app/Contents/Developer" || warn "Could not set Xcode path"
                sudo xcodebuild -license accept 2>/dev/null || warn "Could not accept Xcode license"
            else
                warn "Xcode configuration requires admin access. Please run:"
                warn "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
                warn "  sudo xcodebuild -license accept"
            fi
        fi
    fi
}

setup_development_environment() {
    msg "Expo Development Environment Setup v$SCRIPT_VERSION" "$CYAN"

    OS_TYPE=$(detect_os)
    ARCH=$(uname -m)
    info "Detected system: $OS_TYPE ($ARCH architecture)"
    
    check_root
    
    # Configure git early to avoid issues
    configure_git_credentials
    
    decrypt_env_if_needed

    install_homebrew
    install_zsh_via_brew "$@"
    install_oh_my_zsh
    install_packages
    install_xcode

    local elapsed=$(( $(/bin/date +%s 2>/dev/null || echo 0) - START_TIME ))
    msg "Environment setup complete! Time elapsed: $((elapsed/60))m $((elapsed%60))s" "$GREEN"
}

load_config() {
    local env_file="$1"
    
    if [ ! -f "$env_file" ]; then
        error "Configuration file $env_file not found - ensure git-crypt is unlocked"
    fi
    
    info "Loading project configuration from .env file"
    
    if ! source "$env_file" 2>/dev/null; then
        error "Failed to parse .env configuration file"
    fi
    
    if [ -z "${PROJECTS:-}" ] || [ ${#PROJECTS[@]} -eq 0 ]; then
        error "No projects defined in .env file - check PROJECTS array"
    fi
    
    success "Successfully loaded ${#PROJECTS[@]} project(s) from configuration"
}

show_project_menu() {
    msg "Available Expo Projects:" "$CYAN"
    echo ""
    
    local i=1
    for project in "${PROJECTS[@]}"; do
        IFS='|' read -r name repo <<< "$project"
        printf "  %s[%d]%s %s\n" "$YELLOW" "$i" "$NC" "$name"
        ((i++))
    done
    echo ""
}

get_project_selection() {
    local selection="$1"
    
    if [ -z "$selection" ]; then
        show_project_menu
        printf "%sEnter project number: %s" "$CYAN" "$NC"
        read -r selection
    fi
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#PROJECTS[@]}" ]; then
        error "Invalid project selection: $selection"
    fi
    
    echo "$selection"
}

configure_git_credentials() {
    # Configure git user if not already set
    if [ -z "$(git config --global user.name)" ]; then
        local git_user="${GIT_USER_NAME:-$USER}"
        info "Setting git user name to: $git_user"
        git config --global user.name "$git_user"
    fi
    
    if [ -z "$(git config --global user.email)" ]; then
        local git_email="${GIT_USER_EMAIL:-$USER@$(hostname)}"
        info "Setting git user email to: $git_email"
        git config --global user.email "$git_email"
    fi
    
    # Configure credential helper to avoid keychain prompts
    git config --global credential.helper 'cache --timeout=3600'
}

authenticate_github() {
    # First ensure git credentials are configured
    configure_git_credentials
    
    if [ -n "${GITHUB_TOKEN:-}" ] && [ "$GITHUB_TOKEN" != "ghp_your_personal_access_token_here" ]; then
        info "Authenticating with GitHub using provided token"
        
        # Configure git to use the token for HTTPS operations
        git config --global url."https://token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
        
        # Also set up credential helper as backup
        git config --global credential.https://github.com.username "token"
        printf "protocol=https\nhost=github.com\nusername=token\npassword=%s\n" "$GITHUB_TOKEN" | git credential-cache store
        
        # Configure gh CLI if available
        echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null || true
        
        # Verify the token works
        if gh auth status >/dev/null 2>&1; then
            success "GitHub authentication verified"
            return 0
        elif curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user >/dev/null 2>&1; then
            success "GitHub token validated"
            return 0
        else
            warn "GitHub token may be invalid - pushes might fail"
            return 1
        fi
    else
        warn "No GitHub token configured - repository will be local only"
        warn "Add GITHUB_TOKEN to your .env file to enable GitHub integration"
        return 1
    fi
}

setup_git_repository() {
    local project_name="$1"
    local repo_url="$2"
    local github_username="${GITHUB_USERNAME:-$(gh api user --jq .login 2>/dev/null || echo "")}"
    local development_branch="${GIT_DEVELOPMENT_BRANCH:-development}"
    local production_branch="${GIT_PRODUCTION_BRANCH:-production}"
    
    info "Initializing git repository for $project_name"
    
    # Ensure git credentials are configured before any commits
    configure_git_credentials
    
    local repo_name
    repo_name="${repo_url##*/}"
    repo_name="${repo_name%.git}"
    
    if [ ! -d ".git" ]; then
        git init || error "Failed to initialize git repository"
    fi
    
    if ! git rev-parse HEAD >/dev/null 2>&1; then
        info "Creating initial commit with all project files"
        # Add all files including the Expo project files
        git add -A
        git commit -m "Initial commit: Expo project setup"
    fi
    
    # Check for any uncommitted files and commit them
    if [ -n "$(git status --porcelain)" ]; then
        info "Adding uncommitted project files"
        git add -A
        git commit -m "Add Expo project files"
    fi
    
    git checkout -B "$development_branch"
    
    if authenticate_github && [ -n "$github_username" ]; then
        info "Configuring GitHub remote repository"
        
        if ! gh repo view "$github_username/$repo_name" >/dev/null 2>&1; then
            info "Creating new GitHub repository: $repo_name"
            gh repo create "$repo_name" --public --description "Expo project: $project_name" --clone=false || warn "Could not create remote repo"
        fi
        
        # Use HTTPS with credential helper configured
        git remote add origin "https://github.com/$github_username/$repo_name.git" 2>/dev/null || true
        
        info "Pushing to GitHub development branch"
        # Use GIT_TERMINAL_PROMPT=0 to prevent any interactive prompts
        if ! GIT_TERMINAL_PROMPT=0 git push -q -u origin "$development_branch" 2>/dev/null; then
            warn "Could not push to remote - check GitHub authentication"
        fi
        
        info "Creating production branch"
        git checkout -B "$production_branch"
        if ! GIT_TERMINAL_PROMPT=0 git push -q -u origin "$production_branch" 2>/dev/null; then
            warn "Could not push production branch"
        fi
        git checkout "$development_branch"
        
        success "Git repository configured with remote on GitHub"
    else
        success "Local git repository initialized"
    fi
}

create_expo_project() {
    local project_name="$1"
    local repo_url="$2"
    
    info "Creating new Expo React Native project: $project_name"
    
    # Suppress deprecation warnings
    export NODE_NO_WARNINGS=1
    export npm_config_yes=true
    export CI=false
    export EXPO_NO_TELEMETRY=1
    
    # Create the project, filtering out deprecation warnings for cleaner output
    yarn create expo-app "$project_name" --template blank 2>&1 | /usr/bin/grep -v "DeprecationWarning" | /usr/bin/grep -v "deprecated" || true
    
    # Check if the project was actually created
    if [ ! -d "$project_name" ]; then
        error "Failed to create Expo project - directory not found"
    fi
    
    cd "$project_name" || error "Failed to enter project directory"
    
    # Ensure .gitignore is properly configured before committing
    if [ ! -f ".gitignore" ]; then
        cat > .gitignore << 'EOF'
node_modules/
.expo/
dist/
npm-debug.*
*.jks
*.p8
*.p12
*.key
*.mobileprovision
*.orig.*
web-build/

# macOS
.DS_Store

# Temporary files created by Metro to check the health of the file watcher
.metro-health-check*

# testing
/coverage
EOF
    fi
    
    setup_git_repository "$project_name" "$repo_url"
    cd .. || error "Failed to return to parent directory"
    
    success "Expo project created and initialized"
}

setup_project() {
    local project_name="$1"
    local repo_url="$2"
    
    local sub_projects_dir="$SCRIPT_DIR/subProjects"
    if [ ! -d "$sub_projects_dir" ]; then
        info "Creating subProjects directory for project storage"
        mkdir -p "$sub_projects_dir" || error "Failed to create subProjects directory"
    fi
    
    cd "$sub_projects_dir" || error "Failed to enter subProjects directory"
    
    if [ -d "$project_name" ]; then
        success "Project $project_name already exists locally"
        return 0
    fi
    
    if git ls-remote "$repo_url" >/dev/null 2>&1; then
        info "Repository exists - cloning from $repo_url"
        git clone "$repo_url" "$project_name" || error "Failed to clone repository"
        success "Project cloned successfully"
    else
        info "Repository not found - creating new project"
        create_expo_project "$project_name" "$repo_url"
    fi
}

install_and_start() {
    local project_name="$1"
    local project_path="$SCRIPT_DIR/subProjects/$project_name"
    
    if [ ! -d "$project_path" ]; then
        error "Project directory not found: $project_path"
    fi
    
    cd "$project_path" || error "Failed to enter project directory"
    
    if [ ! -d "node_modules" ]; then
        info "Installing project dependencies with Yarn"
        NODE_NO_WARNINGS=1 yarn install 2>&1 | /usr/bin/grep -v "deprecated" | /usr/bin/grep -v "DeprecationWarning" || true
        # Check if node_modules was actually created
        if [ ! -d "node_modules" ]; then
            error "Failed to install dependencies - node_modules not created"
        fi
        success "All dependencies installed"
    else
        info "Dependencies already installed"
    fi

    local session_name="expo-$project_name"
    tmux kill-session -t "$session_name" 2>/dev/null || true
    info "Creating new tmux session: $session_name"
    tmux new-session -d -s "$session_name" -c "$project_path"
    tmux send-keys -t "$session_name" "npx expo start -i -a" C-m
    success "Expo server started in tmux session"

}

info "Initializing Expo project launcher..."
setup_development_environment "$@"

if [ -z "$ZSH_VERSION" ]; then
    info "Restarting in zsh shell..."
    exec /bin/zsh "$0" "$@"
fi

load_config "$SCRIPT_DIR/.env"

selection=$(get_project_selection "$PROJECT_SELECTION")

counter=1
PROJECT_NAME=""
REPO_URL=""
for project in "${PROJECTS[@]}"; do
    if [ "$counter" -eq "$selection" ]; then
        IFS='|' read -r PROJECT_NAME REPO_URL <<< "$project"
        break
    fi
    ((counter++))
done

if [ -z "$PROJECT_NAME" ]; then
    error "Failed to parse project configuration"
fi

msg "Selected project: $PROJECT_NAME" "$GREEN"

setup_project "$PROJECT_NAME" "$REPO_URL"
install_and_start "$PROJECT_NAME"
