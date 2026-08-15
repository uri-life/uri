#!/bin/sh
# inherit.sh - Inheritance utilities
# POSIX-compatible shell script

# Parse a legacy inheritance string
# Input: "v4.3.2+uri1.23" or "uri1.23"
# Output: upstream_version|patchset_version
parse_legacy_inherits() {
    _pli_value="$1"

    case "$_pli_value" in
        *+*)
            _pli_upstream=${_pli_value%%+*}
            _pli_patchset=${_pli_value#*+}
            printf '%s|%s\n' "$_pli_upstream" "$_pli_patchset"
            ;;
        *)
            printf '|%s\n' "$_pli_value"
            ;;
    esac
}

read_inheritance_parent() {
    _rip_manifest="$1"
    _rip_current_upstream="$2"
    _rip_type=$(yaml_inherits_type "$_rip_manifest")
    _inherit_upstream_version=""
    _inherit_patchset_version=""

    case "$_rip_type" in
        '!!null')
            return 1
            ;;
        '!!map')
            _rip_unknown=$(yq eval '.inherits | keys | map(select(. != "upstream-version" and . != "patchset-version")) | .[0] // ""' "$_rip_manifest")
            [ -z "$_rip_unknown" ] || die "Unknown inherits setting: $_rip_unknown ($_rip_manifest)"
            _rip_upstream_tag=$(yq eval '.inherits."upstream-version" | tag' "$_rip_manifest")
            _rip_patchset_tag=$(yq eval '.inherits."patchset-version" | tag' "$_rip_manifest")
            if [ "$_rip_upstream_tag" != "!!str" ] || [ "$_rip_patchset_tag" != "!!str" ]; then
                die "The inherits version values must be strings: $_rip_manifest"
            fi
            _inherit_upstream_version=$(yaml_get_inherits_upstream_version "$_rip_manifest")
            _inherit_patchset_version=$(yaml_get_inherits_patchset_version "$_rip_manifest")
            [ -n "$_inherit_upstream_version" ] || die "inherits.upstream-version is required: $_rip_manifest"
            [ -n "$_inherit_patchset_version" ] || die "inherits.patchset-version is required: $_rip_manifest"
            ;;
        '!!str')
            _rip_legacy=$(yaml_get_inherits "$_rip_manifest")
            _rip_parsed=$(parse_legacy_inherits "$_rip_legacy")
            _inherit_upstream_version=${_rip_parsed%%|*}
            _inherit_patchset_version=${_rip_parsed#*|}
            [ -n "$_inherit_upstream_version" ] || _inherit_upstream_version="$_rip_current_upstream"
            ;;
        *)
            die "inherits must be a string or object: $_rip_manifest"
            ;;
    esac

    validate_identifier "inherits upstream_version" "$_inherit_upstream_version"
    validate_identifier "inherits patchset_version" "$_inherit_patchset_version"
}

# Build a manifest path
# Usage: resolve_manifest_path "v4.3.2" "uri1.23"
resolve_manifest_path() {
    _upstream_version="$1"
    _patchset_version="$2"
    echo "${URI_ROOT}/versions/${_upstream_version}/patches/${_patchset_version}/manifest.yaml"
}

# Build a patch directory path
# Usage: resolve_patch_dir "v4.3.2" "uri1.23"
resolve_patch_dir() {
    _upstream_version="$1"
    _patchset_version="$2"
    echo "${URI_ROOT}/versions/${_upstream_version}/patches/${_patchset_version}"
}

# Build a patch file path
# Usage: resolve_patch_path "v4.3.2" "uri1.23" "custom_emoji"
resolve_patch_path() {
    _upstream_version="$1"
    _patchset_version="$2"
    _feature="$3"
    echo "${URI_ROOT}/versions/${_upstream_version}/patches/${_patchset_version}/${_feature}.patch"
}

# Collect all manifest paths along the inheritance chain
# Usage: get_inheritance_chain "v4.3.2" "uri1.23"
# Output: manifest paths separated by newlines, ordered from child to ancestor
get_inheritance_chain() {
    _upstream_version="$1"
    _patchset_version="$2"
    _visited=$(make_temp)

    _get_chain_recursive "$_upstream_version" "$_patchset_version" "$_visited"
}

# Traverse the inheritance chain recursively (internal function)
_get_chain_recursive() {
    _upstream_version="$1"
    _patchset_version="$2"
    _visited="$3"

    _manifest=$(resolve_manifest_path "$_upstream_version" "$_patchset_version")

    # Check that the file exists
    if [ ! -f "$_manifest" ]; then
        die "Could not find manifest: $_manifest"
    fi

    # Detect circular inheritance
    if grep -q "^${_manifest}$" "$_visited" 2>/dev/null; then
        die "Circular inheritance detected: $_manifest"
    fi

    # Record the visit
    echo "$_manifest" >> "$_visited"

    # Print the current manifest
    echo "$_manifest"

    # Check for inheritance
    if read_inheritance_parent "$_manifest" "$_upstream_version"; then
        _get_chain_recursive "$_inherit_upstream_version" "$_inherit_patchset_version" "$_visited"
    fi
}

# Resolve inheritance and return merged features as a temporary manifest path
# Usage: resolve_inheritance "v4.3.2" "uri1.23"
# Output: path to a temporary manifest containing the merged features
resolve_inheritance() {
    resolve_inheritance_with_manifest "$1" "$2" ""
}

# Resolve inheritance using a candidate file in place of the current manifest.
# This validates the result before exclude/include changes the original.
resolve_inheritance_with_manifest() {
    _ri_upstream_version="$1"
    _ri_patchset_version="$2"
    _ri_override="${3:-}"
    _ri_target_manifest=$(resolve_manifest_path "$_ri_upstream_version" "$_ri_patchset_version")

    # Get the inheritance chain from child to ancestor
    _ri_chain=$(get_inheritance_chain "$_ri_upstream_version" "$_ri_patchset_version")

    # Reverse it so manifests merge from ancestor to child and children override ancestors
    _ri_reversed=$(echo "$_ri_chain" | reverse_lines)

    # Temporary file for the merged result
    _ri_merged=$(make_temp)
    echo "features: {}" > "$_ri_merged"

    for _ri_manifest in $_ri_reversed; do
        _ri_effective_manifest="$_ri_manifest"
        if [ -n "$_ri_override" ] && [ "$_ri_manifest" = "$_ri_target_manifest" ]; then
            _ri_effective_manifest="$_ri_override"
        fi

        yaml_validate_excludes "$_ri_effective_manifest"
        _ri_excludes=$(yaml_list_excludes "$_ri_effective_manifest")

        # At each stage, excludes may name only inherited features.
        for _ri_excluded in $_ri_excludes; do
            if yaml_has_feature "$_ri_effective_manifest" "$_ri_excluded"; then
                die "A feature cannot be declared and excluded in the same manifest: $_ri_excluded ($_ri_manifest)"
            fi
            if ! yaml_has_feature "$_ri_merged" "$_ri_excluded"; then
                die "Could not find inherited feature: $_ri_excluded ($_ri_manifest)"
            fi
        done

        # Merge the current features, then apply this stage's exclusions.
        if yaml_has "$_ri_effective_manifest" ".features"; then
            yq eval-all '(select(fileIndex == 0).features // {}) * (select(fileIndex == 1).features // {}) | {"features": .}' \
                "$_ri_merged" "$_ri_effective_manifest" > "${_ri_merged}.tmp"
            mv "${_ri_merged}.tmp" "$_ri_merged"
        fi

        for _ri_excluded in $_ri_excludes; do
            yaml_delete_feature "$_ri_merged" "$_ri_excluded"
        done
    done

    _validate_resolved_dependencies "$_ri_merged" "$_ri_target_manifest"
    echo "$_ri_merged"
}

# Verify that all regular and development dependencies of the final active features exist.
_validate_resolved_dependencies() {
    _vrd_manifest="$1"
    _vrd_source_manifest="$2"
    _vrd_missing=$(make_temp)
    : > "$_vrd_missing"

    _vrd_features=$(yaml_list_features "$_vrd_manifest")
    for _vrd_feature in $_vrd_features; do
        validate_identifier "feature" "$_vrd_feature"
        _vrd_dependencies=$(yaml_get_feature_dependencies "$_vrd_manifest" "$_vrd_feature" 2>/dev/null)
        for _vrd_dependency in $_vrd_dependencies; do
            [ -z "$_vrd_dependency" ] || [ "$_vrd_dependency" = "null" ] || validate_identifier "feature dependency" "$_vrd_dependency"
            if [ -n "$_vrd_dependency" ] && [ "$_vrd_dependency" != "null" ] && \
                ! yaml_has_feature "$_vrd_manifest" "$_vrd_dependency"; then
                printf '%s|dependencies|%s\n' "$_vrd_feature" "$_vrd_dependency" >> "$_vrd_missing"
            fi
        done

        _vrd_dev_dependencies=$(yaml_get_feature_dev_dependencies "$_vrd_manifest" "$_vrd_feature" 2>/dev/null)
        for _vrd_dependency in $_vrd_dev_dependencies; do
            [ -z "$_vrd_dependency" ] || [ "$_vrd_dependency" = "null" ] || validate_identifier "feature dependency" "$_vrd_dependency"
            if [ -n "$_vrd_dependency" ] && [ "$_vrd_dependency" != "null" ] && \
                ! yaml_has_feature "$_vrd_manifest" "$_vrd_dependency"; then
                printf '%s|dev-dependencies|%s\n' "$_vrd_feature" "$_vrd_dependency" >> "$_vrd_missing"
            fi
        done
    done

    if [ -s "$_vrd_missing" ]; then
        warn "Missing feature dependencies: $_vrd_source_manifest"
        while IFS='|' read -r _vrd_feature _vrd_kind _vrd_dependency; do
            printf '  - %s.%s -> %s\n' "$_vrd_feature" "$_vrd_kind" "$_vrd_dependency" >&2
        done < "$_vrd_missing"
        die "Could not resolve manifest dependencies."
    fi
}

# Return the merged feature list
# Usage: get_all_features "v4.3.2" "uri1.23"
get_all_features() {
    _upstream_version="$1"
    _patchset_version="$2"

    _merged=$(resolve_inheritance "$_upstream_version" "$_patchset_version")
    yaml_list_features "$_merged"
}

# Check whether a feature exists, including inherited features
# Usage: if has_feature "v4.3.2" "uri1.23" "custom_emoji"; then ...
has_feature() {
    _upstream_version="$1"
    _patchset_version="$2"
    _feature="$3"

    _merged=$(resolve_inheritance "$_upstream_version" "$_patchset_version")
    yaml_has_feature "$_merged" "$_feature"
}

# Find a feature's patch file path in the inheritance chain
# Usage: find_patch_file "v4.3.2" "uri1.23" "custom_emoji"
find_patch_file() {
    _upstream_version="$1"
    _patchset_version="$2"
    _feature="$3"

    # Search the inheritance chain for the patch file, starting with the child
    _chain=$(get_inheritance_chain "$_upstream_version" "$_patchset_version")

    for _manifest in $_chain; do
        _patch_dir=$(dirname "$_manifest")
        _patch_file="${_patch_dir}/${_feature}.patch"

        if [ -f "$_patch_file" ]; then
            echo "$_patch_file"
            return 0
        fi
    done

    return 1
}

# Find a named patch file path in the inheritance chain
# Usage: find_named_patch_file "v4.3.2" "uri1.23" "custom_emoji~ANTE"
find_named_patch_file() {
    _upstream_version="$1"
    _patchset_version="$2"
    _patch_name="$3"

    _chain=$(get_inheritance_chain "$_upstream_version" "$_patchset_version")

    for _manifest in $_chain; do
        _patch_dir=$(dirname "$_manifest")
        _patch_file="${_patch_dir}/${_patch_name}.patch"

        if [ -f "$_patch_file" ]; then
            echo "$_patch_file"
            return 0
        fi
    done

    return 1
}

# Find a pre-apply patch
# Usage: find_ante_patch "v4.3.2" "uri1.23" "feature"
find_ante_patch() {
    _upstream_version="$1"
    _patchset_version="$2"
    _feature="$3"

    find_named_patch_file "$_upstream_version" "$_patchset_version" "${_feature}~ANTE"
}

# Find a post-apply patch
# Usage: find_post_patch "v4.3.2" "uri1.23" "feature"
find_post_patch() {
    _upstream_version="$1"
    _patchset_version="$2"
    _feature="$3"

    find_named_patch_file "$_upstream_version" "$_patchset_version" "${_feature}~POST"
}

# Find a pair-resolution patch
# Usage: find_pair_resolution_patch "v4.3.2" "uri1.23" "current" "completed"
find_pair_resolution_patch() {
    _upstream_version="$1"
    _patchset_version="$2"
    _current="$3"
    _completed="$4"

    find_named_patch_file "$_upstream_version" "$_patchset_version" "${_current}~${_completed}"
}

# Find an applicable pair-resolution patch from a sorted feature list and current index
# Usage: find_applicable_pair_resolution_patch "v4.3.2" "uri1.23" "current" "a b c" "2"
find_applicable_pair_resolution_patch() {
    _upstream_version="$1"
    _patchset_version="$2"
    _current="$3"
    _features_str="$4"
    _current_index="$5"

    _count=0
    _completed=""
    for _feature in $_features_str; do
        if [ "$_count" -lt "$_current_index" ]; then
            _completed="${_completed}
${_feature}"
        fi
        _count=$((_count + 1))
    done

    for _completed_feature in $(printf '%s\n' "$_completed" | sed '/^$/d' | reverse_lines); do
        _patch=$(find_pair_resolution_patch "$_upstream_version" "$_patchset_version" "$_current" "$_completed_feature" || true)
        if [ -n "$_patch" ]; then
            echo "$_patch"
            return 0
        fi
    done

    return 1
}
