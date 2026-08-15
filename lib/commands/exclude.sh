#!/bin/sh
# exclude.sh - exclude/include command implementation
# POSIX-compatible shell script

exclude_usage() {
    cat <<EOF
Usage: uri exclude <upstream_version> <patchset_version> <feature>

Exclude a feature inherited by the current patchset version.

Arguments:
  upstream_version   Upstream version (for example, v1.2.3)
  patchset_version   Patchset version (for example, patch1.0)
  feature            Name of the inherited feature to exclude

Options:
  -h, --help         Print this help text
EOF
}

include_usage() {
    cat <<EOF
Usage: uri include <upstream_version> <patchset_version> <feature>

Include a feature directly excluded by the current patchset version.

Arguments:
  upstream_version   Upstream version (for example, v1.2.3)
  patchset_version   Patchset version (for example, patch1.0)
  feature            Name of the feature to include again

Options:
  -h, --help         Print this help text
EOF
}

cmd_exclude() {
    require_uri_root
    load_uri_config

    _ce_upstream_version=""
    _ce_patchset_version=""
    _ce_feature=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                exclude_usage
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                if [ -z "$_ce_upstream_version" ]; then
                    _ce_upstream_version="$1"
                elif [ -z "$_ce_patchset_version" ]; then
                    _ce_patchset_version="$1"
                elif [ -z "$_ce_feature" ]; then
                    _ce_feature="$1"
                else
                    die "Too many arguments: $1"
                fi
                ;;
        esac
        shift
    done

    if [ -z "$_ce_upstream_version" ] || [ -z "$_ce_patchset_version" ] || [ -z "$_ce_feature" ]; then
        die "upstream_version, patchset_version, and feature are all required. See 'uri exclude --help'."
    fi
    validate_identifier "upstream_version" "$_ce_upstream_version"
    validate_identifier "patchset_version" "$_ce_patchset_version"
    validate_identifier "feature" "$_ce_feature"

    _ce_manifest=$(resolve_manifest_path "$_ce_upstream_version" "$_ce_patchset_version")
    require_file "$_ce_manifest" "Could not find manifest: $_ce_manifest"
    yaml_validate_excludes "$_ce_manifest"

    if yaml_has_feature "$_ce_manifest" "$_ce_feature"; then
        die "A feature declared directly by the current manifest cannot be excluded. Use 'uri remove': $_ce_feature"
    fi
    if yaml_excludes_feature "$_ce_manifest" "$_ce_feature"; then
        die "Feature is already excluded: $_ce_feature"
    fi

    _ce_resolved=$(resolve_inheritance "$_ce_upstream_version" "$_ce_patchset_version")
    if ! yaml_has_feature "$_ce_resolved" "$_ce_feature"; then
        die "Could not find active inherited feature: $_ce_feature"
    fi

    _tmp=""
    make_temp >/dev/null
    _ce_candidate="$_tmp"
    cp "$_ce_manifest" "$_ce_candidate"
    yaml_append_exclude "$_ce_candidate" "$_ce_feature"
    resolve_inheritance_with_manifest "$_ce_upstream_version" "$_ce_patchset_version" "$_ce_candidate" >/dev/null

    yaml_append_exclude "$_ce_manifest" "$_ce_feature"
    success "Excluded feature: $_ce_feature"
}

cmd_include() {
    require_uri_root
    load_uri_config

    _ci_upstream_version=""
    _ci_patchset_version=""
    _ci_feature=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                include_usage
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                if [ -z "$_ci_upstream_version" ]; then
                    _ci_upstream_version="$1"
                elif [ -z "$_ci_patchset_version" ]; then
                    _ci_patchset_version="$1"
                elif [ -z "$_ci_feature" ]; then
                    _ci_feature="$1"
                else
                    die "Too many arguments: $1"
                fi
                ;;
        esac
        shift
    done

    if [ -z "$_ci_upstream_version" ] || [ -z "$_ci_patchset_version" ] || [ -z "$_ci_feature" ]; then
        die "upstream_version, patchset_version, and feature are all required. See 'uri include --help'."
    fi
    validate_identifier "upstream_version" "$_ci_upstream_version"
    validate_identifier "patchset_version" "$_ci_patchset_version"
    validate_identifier "feature" "$_ci_feature"

    _ci_manifest=$(resolve_manifest_path "$_ci_upstream_version" "$_ci_patchset_version")
    require_file "$_ci_manifest" "Could not find manifest: $_ci_manifest"
    yaml_validate_excludes "$_ci_manifest"

    if ! yaml_excludes_feature "$_ci_manifest" "$_ci_feature"; then
        die "Feature is not excluded by the current manifest: $_ci_feature"
    fi

    _tmp=""
    make_temp >/dev/null
    _ci_candidate="$_tmp"
    cp "$_ci_manifest" "$_ci_candidate"
    yaml_remove_exclude "$_ci_candidate" "$_ci_feature"
    resolve_inheritance_with_manifest "$_ci_upstream_version" "$_ci_patchset_version" "$_ci_candidate" >/dev/null

    yaml_remove_exclude "$_ci_manifest" "$_ci_feature"
    success "Included feature: $_ci_feature"
}
