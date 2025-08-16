#!/bin/sh
# Shared functions and colors for all scripts

# Colors that work in sh/bash/zsh
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly CYAN=$'\033[0;36m'
readonly NC=$'\033[0m'

# Message functions
msg() { printf '%s%s%s\n' "${2:-$GREEN}" "$1" "$NC"; }
error() { msg "$1" "$RED"; exit 1; }
success() { msg "$1"; }
warn() { msg "$1" "$YELLOW"; }
info() { msg "$1" "$CYAN"; }
