#!/bin/bash
set -eE
trap 'error "Command failed at line $LINENO: $BASH_COMMAND"' ERR

readonly STANDARD_PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin"
export PATH="$STANDARD_PATH:$PATH"

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly CYAN=$'\033[0;36m'
readonly NC=$'\033[0m'
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
    "zsh:Z Shell"
    "vim:Vim Editor"
    "xclip:X11 Clipboard"
    "qemu:QEMU Virtualizer"
    "lima:Lima VM"
    "colima:Colima Container Runtime"
    "lima-additional-guestagents:Lima Guest Agents"
    "docker:Docker CLI"
    "docker-buildx:Docker Buildx"
    "kubernetes-cli:Kubernetes CLI"
    "yq:YAML Processor"
    "jq:JSON Processor"
    "rsync:Rsync File Sync"
    "skaffold:Skaffold K8s Tool"
    "awscli:AWS CLI"
    "gettext:GNU Gettext"
    "helm:Helm K8s Package Manager"
    "kustomize:Kustomize K8s Tool"
    "instantclient-basic:Oracle Instant Client Basic"
    "instantclient-sdk:Oracle Instant Client SDK"
    "instantclient-tools:Oracle Instant Client Tools"
    "instantclient-sqlplus:Oracle SQL*Plus"
    "tfenv:Terraform Version Manager"
    "fastlane:Fastlane Deployment"
)

readonly CASK_PACKAGES=(
    "google-chrome:Google Chrome"
    "android-studio:Android Studio"
    "claude:Claude Desktop App"
    "claude-code:Claude Code CLI"
    "intellij-idea:IntelliJ IDEA Ultimate"
    "rectangle:Rectangle"
    "iterm2:iTerm2"
    "powershell:PowerShell"
)

readonly NPM_PACKAGES=(
    "@nestjs/cli:nest:NestJS CLI"
    "eas-cli:eas:Expo Application Services CLI"
    "create-expo-app:create-expo-app:Create Expo App"
    "typescript:tsc:TypeScript Compiler"
)

OS_TYPE=""
ARCH=""
UPGRADE_MODE=""
PROJECT_NUMBER=""
PROJECT_NAME=""
REPO_URL=""

msg() { printf '%s%s%s\n' "${2:-$GREEN}" "$1" "$NC"; }
error() { msg "ERROR: $1" "$RED"; exit 1; }
success() { msg "$1"; }
warn() { msg "$1" "$YELLOW"; }
info() { msg "$1" "$CYAN"; }

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
    
    if [ -f "$SCRIPT_DIR/.env" ] && command -v file >/dev/null && file "$SCRIPT_DIR/.env" | grep -q "ASCII text"; then
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
        cd - >/dev/null
        if [ ! -f "$SCRIPT_DIR/.env" ]; then
            error "No .env file found and git-crypt failed"
        fi
    fi
}

install_homebrew() {
    info "Setting up Homebrew package manager"

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

install_zsh_via_brew_and_switch_to_zsh() {
    info "Ensuring zsh shell is available"

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
        # Pass the STANDARD_PATH when switching shells
        exec env PATH="$STANDARD_PATH:$PATH" STANDARD_PATH="$STANDARD_PATH" /bin/zsh "$0" "$@"
    fi

    # After switching to zsh, ensure PATH includes standard directories
    export PATH="$STANDARD_PATH:$PATH"
    success "Running in zsh environment"
}

install_oh_my_zsh() {
    info "Setting up Oh-My-Zsh framework"

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
        sed -i.bak 's/ZSH_THEME="ys"/ZSH_THEME="ys"/' "$zshrc" 2>/dev/null || true
        
        local plugins="plugins=(git brew node npm yarn"
        [ "$OS_TYPE" = "macos" ] && plugins="$plugins macos"
        plugins="$plugins)"
        sed -i.bak "s/plugins=(git)/$plugins/" "$zshrc" 2>/dev/null || true
    fi
    
    success "Shell environment configured"
}

configure_git_credentials() {
    info "Configure git user if not already set"
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

    git config --global credential.helper 'cache --timeout=3600'
}

get_or_read_script_arguments() {    
    local REQUIRED_ARGS_COUNT=2
    
    if [ $# -gt 0 ] && [ $# -ne $REQUIRED_ARGS_COUNT ]; then
        error "Invalid number of arguments."
    fi
    
    if [ $# -eq $REQUIRED_ARGS_COUNT ]; then
        UPGRADE_MODE="$1"
        PROJECT_NUMBER="$2"
    fi
    
    if [ -z "$UPGRADE_MODE" ]; then
        info "Select dependency upgrade mode:"
        echo "  ${YELLOW}[1]${NC} Standard mode - Check installed packages only"
        echo "  ${YELLOW}[2]${NC} Upgrade mode - Update all packages to latest versions"
        echo ""
        printf "${CYAN}Enter upgrade mode (1-2): ${NC}"
        read -r UPGRADE_MODE
    fi
    
    if ! [[ "$UPGRADE_MODE" =~ ^[1-2]$ ]]; then
        error "Invalid upgrade mode: $UPGRADE_MODE (must be 1 or 2)"
    fi

    if [ -z "$PROJECT_NUMBER" ]; then
        info "Available Expo Projects:"
        echo ""
        
        local i=1
        for project in "${PROJECTS[@]}"; do
            IFS='|' read -r name repo <<< "$project"
            printf "  ${YELLOW}[%d]${NC} %s\n" "$i" "$name"
            ((i++))
        done
        echo ""
        printf "${CYAN}Enter project number (1-${#PROJECTS[@]}): ${NC}"
        read -r PROJECT_NUMBER
    fi
    
    local counter=1
    PROJECT_NAME=""
    REPO_URL=""
    for project in "${PROJECTS[@]}"; do
        if [ "$counter" -eq "$PROJECT_NUMBER" ]; then
            IFS='|' read -r PROJECT_NAME REPO_URL <<< "$project"
            break
        fi
        ((counter++))
    done
    
    if [ -z "$PROJECT_NAME" ]; then
        error "Invalid project number: $PROJECT_NUMBER (must be between 1 and ${#PROJECTS[@]})"
    fi
    
    msg "Configuration:" "$CYAN"
    msg "Upgrade Mode: $UPGRADE_MODE" "$GREEN"
    msg "Selected Project: $PROJECT_NAME" "$GREEN"
    echo ""
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
        info "Checking $display"
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
            info "Checking $display"
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

    if [ ${#NPM_PACKAGES[@]} -gt 0 ] && [[ ! "${NPM_PACKAGES[0]}" =~ ^#.*$ ]]; then
        for package in "${NPM_PACKAGES[@]}"; do
            local name="${package%%:*}"
            local cmd="${package#*:}"
            cmd="${cmd%:*}"
            local display="${package##*:}"
            info "Checking $display"
            
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
    else
        info "No global NPM packages to install - using npx for Expo tools"
    fi
}

install_xcode() {
    [ "$OS_TYPE" != "macos" ] && return
    info "Setting up Xcode for iOS development"
    
    if [ ! -d "/Library/Developer/CommandLineTools" ]; then
        info "Installing Xcode Command Line Tools for compilation support"
        touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        PROD=$(softwareupdate -l | grep "\*.*Command Line" | tail -n 1 | sed 's/^[^C]* //')
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
        if xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode.app/Contents/Developer"; then
            success "Xcode developer tools already configured"
        else
            info "Configuring Xcode developer tools (may require admin password)"
            if sudo -n true 2>/dev/null; then
                sudo xcode-select --switch "/Applications/Xcode.app/Contents/Developer" || warn "Could not set Xcode path"
                sudo xcodebuild -license accept 2>/dev/null || warn "Could not accept Xcode license"
            else
                warn "Xcode configuration requires admin access"
            fi
        fi
    fi
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

authenticate_github() {
    configure_git_credentials
    
    if [ -n "${GITHUB_TOKEN:-}" ] && [ "$GITHUB_TOKEN" != "ghp_your_personal_access_token_here" ]; then
        info "Authenticating with GitHub using provided token"
        
        git config --global url."https://token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
        git config --global credential.https://github.com.username "token"
        printf "protocol=https\nhost=github.com\nusername=token\npassword=%s\n" "$GITHUB_TOKEN" | git credential-cache store
        echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null || true
        
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
    configure_git_credentials
    
    local repo_name
    repo_name="${repo_url##*/}"
    repo_name="${repo_name%.git}"
    
    if [ ! -d ".git" ]; then
        git init || error "Failed to initialize git repository"
    fi
    
    if ! git rev-parse HEAD >/dev/null 2>&1; then
        info "Creating initial commit with all project files"
        git add -A
        git commit -m "Initial commit: Expo project setup"
    fi
    
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
        
        git remote add origin "https://github.com/$github_username/$repo_name.git" 2>/dev/null || true
        
        info "Pushing to GitHub development branch"
        GIT_TERMINAL_PROMPT=0 git push -q -u origin "$development_branch" 2>/dev/null || warn "Could not push to remote - check GitHub authentication"
        
        info "Creating production branch"
        git checkout -B "$production_branch"
        GIT_TERMINAL_PROMPT=0 git push -q -u origin "$production_branch" 2>/dev/null || warn "Could not push production branch"
        git checkout "$development_branch"
        
        success "Git repository configured with remote on GitHub"
    else
        success "Local git repository initialized"
    fi
}

setup_project() {
    local project_name="$1"
    local repo_url="$2"
    local projects_dir="$HOME/Desktop/projects"
    cd "$projects_dir" || error "Failed to enter projects directory"

    if [ -d "$project_name" ]; then
        success "Project $project_name already exists locally"
        return 0
    fi

    if git ls-remote "$repo_url" >/dev/null 2>&1; then
        info "Repository exists - cloning from $repo_url"
        git clone "$repo_url" "$project_name" || error "Failed to clone repository"
        success "Project cloned successfully"
    else
        info "Repository not found - creating new project: $project_name"
        npx --yes create-expo-app@latest "$project_name" --template blank
        
        if [ ! -d "$project_name" ]; then
            error "Failed to create project directory $project_name"
        fi
        
        success "Project directory created successfully"
        cd "$project_name" || error "Failed to enter project directory"
        rm -rf package-lock.json node_modules
        yarn install
        npx expo install --fix

        setup_git_repository "$project_name" "$repo_url"
        cd .. || error "Failed to return to parent directory"
        success "Expo project created and initialized"
    fi
}

install_and_start() {
    local project_name="$1"
    local project_path="$HOME/Desktop/projects/$project_name"
    
    if [ ! -d "$project_path" ]; then
        error "Project directory not found: $project_path"
    fi
    
    cd "$project_path" || error "Failed to enter project directory"
    
    if [ ! -d "node_modules" ]; then
        info "Installing project dependencies"
        NODE_NO_WARNINGS=1 yarn install
        
        if [ ! -d "node_modules" ]; then
            error "Failed to install dependencies - node_modules not created"
        fi
        success "All dependencies installed"
    else
        info "Dependencies already installed - checking for updates"
        if [ "package.json" -nt "node_modules" ]; then
            info "package.json has been updated, reinstalling dependencies"
            NODE_NO_WARNINGS=1 yarn install
        fi
    fi

    local session_name="$project_name"
    tmux kill-session -t "$session_name" 2>/dev/null || true
    info "Creating new tmux session: $session_name"
    tmux new-session -d -s "$session_name" -c "$project_path"
    tmux send-keys -t "$session_name" "npx expo start -i -a" C-m
    success "Expo server started in tmux session"
}

#------------------------------------------
# Environment Setup
#------------------------------------------
msg "Expo Development Environment Setup v$SCRIPT_VERSION" "$CYAN"
OS_TYPE=$(detect_os)
ARCH=$(uname -m)
info "Detected system: $OS_TYPE ($ARCH architecture)"
check_root
install_homebrew
install_zsh_via_brew_and_switch_to_zsh "$@"
decrypt_env_if_needed
configure_git_credentials
install_oh_my_zsh
install_packages
install_xcode
msg "Environment setup complete!" "$GREEN"

#------------------------------------------
# Deploy Project
#------------------------------------------
load_config "$SCRIPT_DIR/.env"
get_or_read_script_arguments "$@"
setup_project "$PROJECT_NAME" "$REPO_URL"
install_and_start "$PROJECT_NAME"
