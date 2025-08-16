#!/bin/sh
# Single launcher script that handles everything

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy.sh"
ENV_FILE="$SCRIPT_DIR/.env"

# Source shared functions
source "$SCRIPT_DIR/.functions.sh"

# Step 1: Run deploy.sh FIRST (installs zsh and everything else)
if [ -f "$DEPLOY_SCRIPT" ]; then
    info "Ensuring environment is ready..."
    /bin/sh "$DEPLOY_SCRIPT" || error "Setup failed"
else
    error "deploy.sh not found"
fi

# Step 2: Now restart in zsh if not already (zsh exists now)
if [ -z "$ZSH_VERSION" ]; then
    exec /bin/zsh "$0" "$@"
fi

# Step 3: Load projects from .env
source "$ENV_FILE" 2>/dev/null || error "No .env file found"

# Step 4: Show menu and get selection
clear
echo "${CYAN}================================${NC}"
echo "${CYAN}     Expo Project Launcher      ${NC}"
echo "${CYAN}================================${NC}"
echo ""

i=1
for project in "${PROJECTS[@]}"; do
    IFS='|' read -r name repo <<< "$project"
    if [ -n "$repo" ]; then
        echo "  ${GREEN}$i)${NC} $name ${YELLOW}[clone from repo]${NC}"
    else
        echo "  ${GREEN}$i)${NC} $name ${CYAN}[create new]${NC}"
    fi
    ((i++))
done

echo ""
echo -n "${CYAN}Select project (1-${#PROJECTS[@]}): ${NC}"
read -r selection

# Parse selected project
IFS='|' read -r PROJECT_NAME REPO_URL <<< "${PROJECTS[$selection]}"

info "Selected: $PROJECT_NAME"

# Step 5: Setup PATH and create/clone project
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.npm-global/bin:$PATH"

if [ ! -d "$PROJECT_NAME" ]; then
    if [ -n "$REPO_URL" ]; then
        info "Cloning from $REPO_URL..."
        git clone "$REPO_URL" "$PROJECT_NAME"
    else
        info "Creating new Expo project: $PROJECT_NAME"
        npx create-expo-app "$PROJECT_NAME" --template blank
    fi
else
    success "Project already exists"
fi

# Step 6: Install dependencies and run
cd "$PROJECT_NAME"
[ ! -d "node_modules" ] && npm install

info "Starting Expo (i=iOS, a=Android, w=Web)..."
npx expo start