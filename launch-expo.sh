#!/bin/sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/.functions.sh"

# Functions specific to this script
ensure_zsh() {
    if [ -z "$ZSH_VERSION" ]; then
        info "Switching to zsh for better compatibility"
        exec /bin/zsh "$0" "$@"
    fi
}

load_config() {
    local env_file="$1"
    source "$env_file" 2>/dev/null || error "Configuration file $env_file not found"
}

show_project_menu() {
    clear
    echo "${CYAN}================================${NC}"
    echo "${CYAN}     Expo Project Launcher      ${NC}"
    echo "${CYAN}================================${NC}"
    echo ""

    local i=1
    for project in "${PROJECTS[@]}"; do
        IFS='|' read -r name repo <<< "$project"
        if [ -n "$repo" ]; then
            echo "  ${GREEN}$i)${NC} $name ${YELLOW}[from repository]${NC}"
        else
            echo "  ${GREEN}$i)${NC} $name ${CYAN}[create new]${NC}"
        fi
        ((i++))
    done

    echo ""
    echo -n "${CYAN}Select project (1-${#PROJECTS[@]}): ${NC}"
    read -r selection
    
    if [ "$selection" -lt 1 ] || [ "$selection" -gt "${#PROJECTS[@]}" ]; then
        error "Invalid selection"
    fi
    
    echo "$selection"
}

check_git_deps() {
    command -v git >/dev/null 2>&1 || error "Git is not installed"
    command -v gh >/dev/null 2>&1 || error "GitHub CLI (gh) is not installed"
    command -v git-flow >/dev/null 2>&1 || error "git-flow is not installed"
}

check_repo_exists() {
    local repo_url="$1"
    git ls-remote "$repo_url" >/dev/null 2>&1
}

create_remote_repo() {
    local repo_name="$1"
    local github_username="$2"
    local description="${3:-Auto-created repository}"
    
    if gh repo view "$github_username/$repo_name" >/dev/null 2>&1; then
        success "Remote repository already exists"
        return 0
    else
        info "Creating remote repository: $repo_name"
        if gh repo create "$repo_name" --public --description "$description" --clone=false; then
            success "Remote repository created successfully"
        else
            error "Failed to create remote repository"
        fi
    fi
}

setup_git_flow() {
    local development_branch="${1:-development}"
    local production_branch="${2:-production}"
    local repo_name="$3"
    local github_username="$4"
    
    if [ ! -d ".git" ]; then
        info "Initializing git repository"
        git init
    fi
    
    if ! git remote get-url origin >/dev/null 2>&1; then
        info "Adding remote origin"
        git remote add origin "https://github.com/$github_username/$repo_name.git"
    fi
    
    if ! git config --get gitflow.branch.master >/dev/null 2>&1; then
        info "Initializing git flow with $development_branch and $production_branch branches"
        
        git flow init -d \
            --force \
            --prefix="feature/" \
            --release-prefix="release/" \
            --hotfix-prefix="hotfix/" \
            --support-prefix="support/" \
            --versiontag-prefix="v"
        
        git config gitflow.branch.master "$production_branch"
        git config gitflow.branch.develop "$development_branch"
        
        success "Git flow initialized"
    fi
    
    git checkout -B "$development_branch"
    
    if ! git rev-parse HEAD >/dev/null 2>&1; then
        echo "# $repo_name" > README.md
        git add README.md
        git commit -m "Initial commit"
    fi
    
    info "Pushing $development_branch branch"
    git push -u origin "$development_branch"
    
    if ! git ls-remote --heads origin "$production_branch" | grep -q "$production_branch"; then
        info "Creating and pushing $production_branch branch"
        git checkout -B "$production_branch"
        git push -u origin "$production_branch"
        git checkout "$development_branch"
    fi
    
    success "Repository setup complete with $development_branch and $production_branch branches"
}

setup_git_repository() {
    local project_name="$1"
    local repo_url="$2"
    local github_username="${GITHUB_USERNAME:-$(gh api user --jq .login 2>/dev/null)}"
    local development_branch="${GIT_DEVELOPMENT_BRANCH:-development}"
    local production_branch="${GIT_PRODUCTION_BRANCH:-production}"
    
    if [ -z "$github_username" ]; then
        warn "Could not determine GitHub username. Please set GITHUB_USERNAME in .env or authenticate with 'gh auth login'"
        return 1
    fi
    
    local repo_name
    repo_name=$(basename "$repo_url" .git)
    
    check_git_deps
    create_remote_repo "$repo_name" "$github_username" "Expo project: $project_name"
    setup_git_flow "$development_branch" "$production_branch" "$repo_name" "$github_username"
}

create_expo_project() {
    local project_name="$1"
    local repo_url="$2"
    
    info "Creating new Expo project: $project_name"
    npx create-expo-app "$project_name" --template blank
    
    cd "$project_name"
    setup_git_repository "$project_name" "$repo_url"
    cd ..
    
    success "Expo project $project_name created and configured"
}

clone_existing_project() {
    local project_name="$1"
    local repo_url="$2"
    
    info "Cloning existing project from $repo_url"
    git clone "$repo_url" "$project_name"
    success "Project $project_name cloned successfully"
}

setup_project() {
    local project_name="$1"
    local repo_url="$2"
    
    export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.npm-global/bin:$PATH"
    
    if [ -d "$project_name" ]; then
        success "Project directory already exists"
        return 0
    fi
    
    if check_repo_exists "$repo_url"; then
        clone_existing_project "$project_name" "$repo_url"
    else
        info "Repository doesn't exist, creating new project with repository"
        create_expo_project "$project_name" "$repo_url"
    fi
}

install_and_start() {
    local project_name="$1"
    
    cd "$project_name"
    
    if [ ! -d "node_modules" ]; then
        info "Installing project dependencies"
        npm install
        success "Dependencies installed"
    fi
    
    info "Starting Expo development server (i=iOS, a=Android, w=Web)"
    npx expo start
}

# Main script execution
/bin/sh "$SCRIPT_DIR/deploy.sh" || error "Environment setup failed"
ensure_zsh "$@"
load_config "$SCRIPT_DIR/.env"

selection=$(show_project_menu)
IFS='|' read -r PROJECT_NAME REPO_URL <<< "${PROJECTS[$selection]}"

info "Selected: $PROJECT_NAME"

setup_project "$PROJECT_NAME" "$REPO_URL"
install_and_start "$PROJECT_NAME"
