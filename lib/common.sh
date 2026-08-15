#!/bin/sh
# common.sh - Shared utility functions
# POSIX-compatible shell script

# Color codes (used only on a TTY)
if [ -t 1 ]; then
    COLOR_RED='\033[0;31m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_GREEN='\033[0;32m'
    COLOR_BLUE='\033[0;34m'
    COLOR_RESET='\033[0m'
else
    COLOR_RED=''
    COLOR_YELLOW=''
    COLOR_GREEN=''
    COLOR_BLUE=''
    COLOR_RESET=''
fi

# Print an error message and exit
# Usage: die "error message"
die() {
    printf "${COLOR_RED}error:${COLOR_RESET} %s\n" "$1" >&2
    exit 1
}

# Print a warning message
# Usage: warn "warning message"
warn() {
    printf "${COLOR_YELLOW}warning:${COLOR_RESET} %s\n" "$1" >&2
}

# Print an informational message
# Usage: info "informational message"
info() {
    printf "${COLOR_BLUE}info:${COLOR_RESET} %s\n" "$1"
}

# Print a success message
# Usage: success "success message"
success() {
    printf "${COLOR_GREEN}success:${COLOR_RESET} %s\n" "$1"
}

# Check whether a command exists
# Usage: require_cmd "yq" "yq is required. brew install yq"
require_cmd() {
    _cmd="$1"
    _msg="${2:-The $_cmd command is required.}"
    if ! command -v "$_cmd" >/dev/null 2>&1; then
        die "$_msg"
    fi
}

# Convert a relative path to an absolute path
# Usage: resolve_path "./relative/path"
resolve_path() {
    _path="$1"
    if [ -d "$_path" ]; then
        # The path is a directory
        (cd "$_path" && pwd)
    elif [ -f "$_path" ]; then
        # The path is a file
        _dir=$(dirname "$_path")
        _base=$(basename "$_path")
        echo "$(cd "$_dir" && pwd)/$_base"
    else
        # The path does not exist; resolve it relative to its parent directory
        _dir=$(dirname "$_path")
        _base=$(basename "$_path")
        if [ -d "$_dir" ]; then
            echo "$(cd "$_dir" && pwd)/$_base"
        else
            # Fall back to the current directory when the parent does not exist
            echo "$(pwd)/$_path"
        fi
    fi
}

# Find URI_ROOT (the directory containing manifest.yaml)
# Search upward from the current directory for manifest.yaml
find_uri_root() {
    _dir="$PWD"
    while [ "$_dir" != "/" ]; do
        if [ -f "$_dir/manifest.yaml" ]; then
            echo "$_dir"
            return 0
        fi
        _dir=$(dirname "$_dir")
    done
    return 1
}

# Set URI_ROOT (required)
# Usage: require_uri_root
require_uri_root() {
    URI_ROOT=$(find_uri_root) || die "Could not find manifest.yaml. Run 'uri init' first."
    export URI_ROOT
}

# Set URI_ROOT when available (used by commands such as init)
# Usage: set_uri_root_if_exists
set_uri_root_if_exists() {
    if URI_ROOT=$(find_uri_root 2>/dev/null); then
        export URI_ROOT
        return 0
    fi
    return 1
}

# Return the upstream version directory path
# Usage: upstream_version_dir "v1.2.3"
upstream_version_dir() {
    echo "${URI_ROOT}/versions/$1"
}

# Return the patchset version directory path
# Usage: patchset_version_dir "v1.2.3" "stack-a"
patchset_version_dir() {
    echo "${URI_ROOT}/versions/$1/patches/$2"
}

# Validate that a value is a single component safe for use in a Git ref path.
# It must start with an ASCII alphanumeric character and may then contain ASCII alphanumerics and +._-.
is_valid_identifier() {
    _ivi_value="$1"
    case "$_ivi_value" in
        "")
            return 1
            ;;
        [!A-Za-z0-9]*|*[!A-Za-z0-9+._-]*|*..*|*.lock)
            return 1
            ;;
    esac
    git check-ref-format "refs/heads/uri/${_ivi_value}" >/dev/null 2>&1
}

validate_identifier() {
    _vi_label="$1"
    _vi_value="$2"

    if [ -z "$_vi_value" ]; then
        die "$_vi_label must not be empty."
    fi
    if ! is_valid_identifier "$_vi_value"; then
        die "Invalid $_vi_label: $_vi_value"
    fi
}

# Validate the final branch name assembled from the components against Git's rules.
validate_branch_ref() {
    _vbr_branch="$1"
    if ! git check-ref-format "refs/heads/${_vbr_branch}" >/dev/null 2>&1; then
        die "Cannot use this as a Git branch name: $_vbr_branch"
    fi
}

# Check whether a file or directory exists
# Usage: require_file "path/to/file" "File not found"
require_file() {
    if [ ! -f "$1" ]; then
        die "${2:-File not found: $1}"
    fi
}

require_dir() {
    if [ ! -d "$1" ]; then
        die "${2:-Directory not found: $1}"
    fi
}

# Create and clean up temporary files
# Used with trap
_TEMP_FILES=""
_TEMP_DIRS=""

make_temp() {
    _tmp=$(mktemp)
    _TEMP_FILES="$_TEMP_FILES $_tmp"
    echo "$_tmp"
}

# Create a temporary directory and store its path in _made_temp_dir.
# Do not invoke this through command substitution, so the cleanup list remains in the current shell.
make_temp_dir() {
    _made_temp_dir=$(mktemp -d)
    _TEMP_DIRS="$_TEMP_DIRS $_made_temp_dir"
}

_cleanup_temp_dir() {
    _cleanup_dir="$1"
    if [ -n "$_cleanup_dir" ] && [ -d "$_cleanup_dir" ]; then
        rm -rf "$_cleanup_dir"
    fi
}

cleanup_temp() {
    for _f in $_TEMP_FILES; do
        rm -f "$_f" 2>/dev/null
    done
    for _d in $_TEMP_DIRS; do
        _cleanup_temp_dir "$_d"
    done
}

# Clean up temporary files when the script exits
trap cleanup_temp EXIT INT TERM
