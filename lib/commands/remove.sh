#!/bin/sh
# remove.sh - remove command implementation
# POSIX-compatible shell script

# Print remove command usage
remove_usage() {
    cat <<EOF
Usage: uri remove <upstream_version> [patchset_version] [feature] [options]

Remove an upstream version, patchset version, or feature.

Arguments:
  upstream_version   Upstream version (for example, v1.2.3+build)
  patchset_version   Patchset version (for example, stack-a)
  feature            Feature name (for example, custom_emoji)

Options:
  -h, --help         Print this help text
  -f, --force        Force deletion without confirmation

Examples:
  uri remove v1.2.3+build                          # Remove an entire upstream version
  uri remove v1.2.3+build stack-a                  # Remove a patchset version
  uri remove v1.2.3+build stack-a custom_emoji     # Remove a feature
EOF
}

# Main remove command function
cmd_remove() {
    require_uri_root
    load_uri_config

    _upstream_version=""
    _patchset_version=""
    _feature=""
    _force=false

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                remove_usage
                exit 0
                ;;
            -f|--force)
                _force=true
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                # Positional argument
                if [ -z "$_upstream_version" ]; then
                    _upstream_version="$1"
                elif [ -z "$_patchset_version" ]; then
                    _patchset_version="$1"
                elif [ -z "$_feature" ]; then
                    _feature="$1"
                else
                    die "Too many arguments: $1"
                fi
                ;;
        esac
        shift
    done

    # Check required arguments
    if [ -z "$_upstream_version" ]; then
        die "upstream_version is required. See 'uri remove --help'."
    fi
    validate_identifier "upstream_version" "$_upstream_version"
    [ -z "$_patchset_version" ] || validate_identifier "patchset_version" "$_patchset_version"
    [ -z "$_feature" ] || validate_identifier "feature" "$_feature"

    # Determine the removal level
    if [ -n "$_feature" ]; then
        _remove_feature "$_upstream_version" "$_patchset_version" "$_feature" "$_force"
    elif [ -n "$_patchset_version" ]; then
        _remove_patchset_version "$_upstream_version" "$_patchset_version" "$_force"
    else
        _remove_upstream_version "$_upstream_version" "$_force"
    fi
}

# Remove a feature (internal function)
_remove_feature() {
    _upstream_version="$1"
    _patchset_version="$2"
    _feature="$3"
    _force="$4"

    _patchset_dir=$(patchset_version_dir "$_upstream_version" "$_patchset_version")
    _manifest="${_patchset_dir}/manifest.yaml"
    _patch_file="${_patchset_dir}/${_feature}.patch"

    # Check for existence
    if [ ! -f "$_manifest" ]; then
        die "Could not find patchset version: $_patchset_dir"
    fi

    if ! yaml_has_feature "$_manifest" "$_feature"; then
        die "Could not find feature: $_feature"
    fi

    # Check whether other features depend on this feature
    _dependents=$(_find_dependents "$_manifest" "$_feature")
    if [ -n "$_dependents" ]; then
        warn "The following features depend on $_feature:"
        for _dep in $_dependents; do
            echo "  - $_dep"
        done
        if [ "$_force" != true ]; then
            die "Dependent features exist. Use -f to force deletion."
        fi
    fi

    # Confirm
    if [ "$_force" != true ]; then
        printf "Delete feature '%s'? [y/N] " "$_feature"
        read -r _confirm
        case "$_confirm" in
            [yY]|[yY][eE][sS]) ;;
            *) die "Canceled." ;;
        esac
    fi

    info "Removing feature $_feature..."

    # Remove it from the manifest
    yaml_delete_feature "$_manifest" "$_feature"

    # Delete the patch file
    if [ -f "$_patch_file" ]; then
        rm -f "$_patch_file"
    fi

    success "Removed feature: $_feature"
}

# Remove a patchset version (internal function)
_remove_patchset_version() {
    _upstream_version="$1"
    _patchset_version="$2"
    _force="$3"

    _patchset_dir=$(patchset_version_dir "$_upstream_version" "$_patchset_version")

    if [ ! -d "$_patchset_dir" ]; then
        die "Could not find patchset version: $_patchset_dir"
    fi

    # Confirm
    if [ "$_force" != true ]; then
        printf "Delete patchset version '%s' and all of its features? [y/N] " "$_patchset_version"
        read -r _confirm
        case "$_confirm" in
            [yY]|[yY][eE][sS]) ;;
            *) die "Canceled." ;;
        esac
    fi

    info "Removing patchset version $_patchset_version..."

    rm -rf "$_patchset_dir"

    success "Removed patchset version: $_patchset_version"
}

# Remove an upstream version (internal function)
_remove_upstream_version() {
    _upstream_version="$1"
    _force="$2"

    _ver_dir=$(upstream_version_dir "$_upstream_version")

    if [ ! -d "$_ver_dir" ]; then
        die "Could not find upstream version: $_ver_dir"
    fi

    # Confirm
    if [ "$_force" != true ]; then
        printf "Delete upstream version '%s' and all of its patchset versions and features? [y/N] " "$_upstream_version"
        read -r _confirm
        case "$_confirm" in
            [yY]|[yY][eE][sS]) ;;
            *) die "Canceled." ;;
        esac
    fi

    info "Removing upstream version $_upstream_version..."

    rm -rf "$_ver_dir"

    success "Removed upstream version: $_upstream_version"
}

# Find other features that depend on a specific feature (internal function)
_find_dependents() {
    _manifest="$1"
    _target="$2"

    _features=$(yaml_list_features "$_manifest")
    _dependents=""

    for _f in $_features; do
        if [ "$_f" = "$_target" ]; then
            continue
        fi

        _deps=$(yaml_get_feature_dependencies "$_manifest" "$_f" 2>/dev/null)
        for _d in $_deps; do
            if [ "$_d" = "$_target" ]; then
                _dependents="$_dependents $_f"
                break
            fi
        done
    done

    echo "$_dependents" | sed 's/^ *//'
}
