#!/bin/sh
# list.sh - list command implementation
# POSIX-compatible shell script

# Print list command usage
list_usage() {
    cat <<EOF
Usage: uri list [upstream_version] [patchset_version] [options]

List versions, patches, or features.

Arguments:
  upstream_version   Upstream version (for example, v1.2.3+build)
  patchset_version   Patchset version (for example, stack-a)

Options:
  -h, --help         Print this help text

Examples:
  uri list                       # List all upstream versions
  uri list v1.2.3+build          # List patchset versions
  uri list v1.2.3+build stack-a  # List features
EOF
}

# Main list command function
cmd_list() {
    _upstream_version=""
    _patchset_version=""

    # Parse options; handle --help before checking uri_root
    for _arg in "$@"; do
        case "$_arg" in
            -h|--help)
                list_usage
                exit 0
                ;;
        esac
    done

    require_uri_root
    load_uri_config

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            -*)
                die "Unknown option: $1"
                ;;
            *)
                # Positional argument
                if [ -z "$_upstream_version" ]; then
                    _upstream_version="$1"
                elif [ -z "$_patchset_version" ]; then
                    _patchset_version="$1"
                else
                    die "Too many arguments: $1"
                fi
                ;;
        esac
        shift
    done

    [ -z "$_upstream_version" ] || validate_identifier "upstream_version" "$_upstream_version"
    [ -z "$_patchset_version" ] || validate_identifier "patchset_version" "$_patchset_version"

    # Dispatch based on the arguments
    if [ -z "$_upstream_version" ]; then
        _list_versions
    elif [ -z "$_patchset_version" ]; then
        _list_patchsets "$_upstream_version"
    else
        _list_features "$_upstream_version" "$_patchset_version"
    fi
}

# Print the version list (internal function)
_list_versions() {
    _versions_dir="${URI_ROOT}/versions"

    if [ ! -d "$_versions_dir" ]; then
        info "No versions."
        return
    fi

    _count=0
    for _ver_path in "$_versions_dir"/*; do
        if [ -d "$_ver_path" ] && is_valid_identifier "$(basename "$_ver_path")"; then
            _ver=$(basename "$_ver_path")
            echo "$_ver"
            _count=$((_count + 1))
        fi
    done

    if [ $_count -eq 0 ]; then
        info "No versions."
    fi
}

# Print the patch list (internal function)
_list_patchsets() {
    _upstream_version="$1"
    _ver_dir=$(upstream_version_dir "$_upstream_version")
    _patches_dir="${_ver_dir}/patches"

    if [ ! -d "$_ver_dir" ]; then
        die "Upstream version $_upstream_version does not exist."
    fi

    if [ ! -d "$_patches_dir" ]; then
        info "No patches."
        return
    fi

    _count=0
    for _patch_manifest in "$_patches_dir"/*/manifest.yaml; do
        if [ -f "$_patch_manifest" ] && is_valid_identifier "$(basename "$(dirname "$_patch_manifest")")"; then
            _patch=$(basename "$(dirname "$_patch_manifest")")
            echo "$_patch"
            _count=$((_count + 1))
        fi
    done

    if [ $_count -eq 0 ]; then
        info "No patches."
    fi
}

# Print the feature list (internal function)
_list_features() {
    _upstream_version="$1"
    _patchset_version="$2"
    _patchset_dir=$(patchset_version_dir "$_upstream_version" "$_patchset_version")
    _manifest="${_patchset_dir}/manifest.yaml"

    if [ ! -d "$_patchset_dir" ]; then
        die "Patchset version $_patchset_version does not exist (upstream $_upstream_version)."
    fi

    if [ ! -f "$_manifest" ]; then
        die "Could not find manifest.yaml: $_manifest"
    fi

    # Extract the final feature list after resolving inheritance and excludes
    _merged=$(resolve_inheritance "$_upstream_version" "$_patchset_version")
    _features=$(yaml_list_features "$_merged")

    if [ -z "$_features" ]; then
        info "No features."
        return
    fi

    echo "$_features"
}
