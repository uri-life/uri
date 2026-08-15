#!/bin/sh
# add.sh - add command implementation
# POSIX-compatible shell script

# Print add command usage
add_usage() {
    cat <<EOF
Usage: uri add <upstream_version> <patchset_version> [feature] [options]

Add a patchset version or feature.

Arguments:
  upstream_version   Upstream version (for example, v1.2.3)
  patchset_version   Patchset version (for example, patch1.0)
  feature            Feature name (for example, feature-a)

Options:
  -h, --help             Print this help text
  --name NAME            Display name for the feature
  --description DESC     Feature description
  --dependencies DEPS    Required features (comma-separated)
  --dev-dependencies DEPS Development-only dependencies (comma-separated)
  --inherits VERSION     Patchset version to inherit
  --inherits-upstream VERSION Upstream version to inherit

Examples:
  uri add v1.2.3 patch1.0                          # Add a patchset version
  uri add v1.2.3 patch1.0 feature-a                # Add a feature
  uri add v1.2.3 patch1.0 feature-a \\
      --name "Feature A" \\
      --description "First change" \\
      --dependencies "base"                        # Include options
EOF
}

# Main add command function
cmd_add() {
    require_uri_root
    load_uri_config

    _upstream_version=""
    _patchset_version=""
    _feature=""
    _name=""
    _description=""
    _dependencies=""
    _dev_dependencies=""
    _inherits=""
    _inherits_upstream=""

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                add_usage
                exit 0
                ;;
            --name)
                shift
                _name="$1"
                ;;
            --description)
                shift
                _description="$1"
                ;;
            --dependencies)
                shift
                _dependencies="$1"
                ;;
            --dev-dependencies)
                shift
                _dev_dependencies="$1"
                ;;
            --inherits)
                shift
                [ $# -gt 0 ] || die "--inherits requires a value."
                _inherits="$1"
                ;;
            --inherits-upstream)
                shift
                [ $# -gt 0 ] || die "--inherits-upstream requires a value."
                _inherits_upstream="$1"
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
        die "upstream_version is required. See 'uri add --help'."
    fi
    validate_identifier "upstream_version" "$_upstream_version"

    # Check the upstream version directory
    _ver_dir=$(upstream_version_dir "$_upstream_version")
    if [ ! -d "$_ver_dir" ]; then
        die "Upstream version $_upstream_version does not exist. Run 'uri init $_upstream_version' first."
    fi

    if [ -z "$_patchset_version" ]; then
        die "patchset_version is required. See 'uri add --help'."
    fi
    validate_identifier "patchset_version" "$_patchset_version"
    [ -z "$_feature" ] || validate_identifier "feature" "$_feature"
    [ -z "$_inherits_upstream" ] || validate_identifier "inherits upstream_version" "$_inherits_upstream"
    _validate_identifier_csv "dependencies" "$_dependencies"
    _validate_identifier_csv "dev-dependencies" "$_dev_dependencies"

    # Add a patchset version or feature
    if [ -z "$_feature" ]; then
        _add_patchset_version "$_upstream_version" "$_patchset_version" "$_inherits" "$_inherits_upstream"
    else
        [ -z "$_inherits" ] || die "--inherits cannot be used when adding a feature."
        [ -z "$_inherits_upstream" ] || die "--inherits-upstream cannot be used when adding a feature."
        _add_feature "$_upstream_version" "$_patchset_version" "$_feature" "$_name" "$_description" "$_dependencies" "$_dev_dependencies"
    fi
}

_validate_identifier_csv() {
    _vic_label="$1"
    _vic_csv="$2"
    [ -n "$_vic_csv" ] || return 0
    _vic_old_ifs="$IFS"
    IFS=','
    for _vic_item in $_vic_csv; do
        _vic_item=$(echo "$_vic_item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$_vic_item" ] || continue
        validate_identifier "$_vic_label feature" "$_vic_item"
    done
    IFS="$_vic_old_ifs"
}

# Add a patchset version (internal function)
_add_patchset_version() {
    _upstream_version="$1"
    _patchset_version="$2"
    _inherits="$3"
    _inherits_upstream="$4"

    _patchset_dir=$(patchset_version_dir "$_upstream_version" "$_patchset_version")
    _manifest="${_patchset_dir}/manifest.yaml"

    if [ -d "$_patchset_dir" ]; then
        die "Patchset version already exists: $_patchset_dir"
    fi

    info "Adding patchset version $_patchset_version..."

    _parent_upstream="$_inherits_upstream"
    _parent_patchset="$_inherits"
    if [ -n "$_inherits" ] && [ -z "$_inherits_upstream" ]; then
        _parsed=$(parse_legacy_inherits "$_inherits")
        _parsed_upstream=${_parsed%%|*}
        _parsed_patchset=${_parsed#*|}
        if [ -n "$_parsed_upstream" ]; then
            _parent_upstream="$_parsed_upstream"
            _parent_patchset="$_parsed_patchset"
        fi
    fi
    [ -z "$_parent_upstream" ] || validate_identifier "inherits upstream_version" "$_parent_upstream"
    [ -z "$_parent_patchset" ] || validate_identifier "inherits patchset_version" "$_parent_patchset"
    if [ -n "$_parent_upstream" ] && [ -z "$_parent_patchset" ]; then
        die "--inherits-upstream requires --inherits PATCHSET_VERSION."
    fi

    # Create the directory
    mkdir -p "$_patchset_dir"

    yq -n '{"excludes": [], "features": {}}' > "$_manifest"
    if [ -n "$_parent_patchset" ]; then
        [ -n "$_parent_upstream" ] || _parent_upstream="$_upstream_version"
        URI_PARENT_UPSTREAM="$_parent_upstream" URI_PARENT_PATCHSET="$_parent_patchset" \
            yq eval -i '.inherits = {"upstream-version": strenv(URI_PARENT_UPSTREAM), "patchset-version": strenv(URI_PARENT_PATCHSET)}' "$_manifest"
    fi

    success "Added patchset version: $_patchset_dir"
}

# Add a feature (internal function)
_add_feature() {
    _upstream_version="$1"
    _patchset_version="$2"
    _feature="$3"
    _name="$4"
    _description="$5"
    _dependencies="$6"
    _dev_dependencies="$7"

    _patchset_dir=$(patchset_version_dir "$_upstream_version" "$_patchset_version")
    _manifest="${_patchset_dir}/manifest.yaml"
    _patch_file="${_patchset_dir}/${_feature}.patch"

    # Check that the patchset version exists
    if [ ! -d "$_patchset_dir" ]; then
        die "Patchset version does not exist: $_patchset_dir. Run 'uri add $_upstream_version $_patchset_version' first."
    fi

    # Check for a duplicate feature
    if yaml_has_feature "$_manifest" "$_feature"; then
        die "Feature already exists: $_feature"
    fi

    info "Adding feature $_feature..."

    # Set defaults
    if [ -z "$_name" ]; then
        _name="$_feature"
    fi
    if [ -z "$_description" ]; then
        _description=""
    fi

    # Build dependencies
    if [ -n "$_dependencies" ]; then
        _dep_array=$(_csv_to_yaml_array "$_dependencies")
    else
        _dep_array="[]"
    fi

    if [ -n "$_dev_dependencies" ]; then
        _dev_dep_array=$(_csv_to_yaml_array "$_dev_dependencies")
    else
        _dev_dep_array="[]"
    fi

    yaml_set_feature "$_manifest" "$_feature" "$_name" "$_description" "$_dep_array" "$_dev_dep_array"

    # Create an empty patch file
    : > "$_patch_file"

    success "Added feature: $_feature"
    info "Patch file: $_patch_file"
}

_csv_to_yaml_array() {
    _csv="$1"
    _array="["
    _first=true
    _old_ifs="$IFS"
    IFS=','
    for _item in $_csv; do
        _item=$(echo "$_item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$_item" ]; then
            continue
        fi
        if [ "$_first" = true ]; then
            _array="${_array}\"$_item\""
            _first=false
        else
            _array="${_array}, \"$_item\""
        fi
    done
    IFS="$_old_ifs"
    _array="${_array}]"

    echo "$_array"
}
