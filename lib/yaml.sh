#!/bin/sh
# yaml.sh - YAML parsing utilities (yq wrapper)
# POSIX-compatible shell script
# Dependency: yq (mikefarah/yq v4+)

# Read a YAML value
# Usage: yaml_get "file.yaml" ".path.to.value"
yaml_get() {
    _file="$1"
    _path="$2"
    yq eval "$_path" "$_file"
}

# Write a YAML value
# Usage: yaml_set "file.yaml" ".path.to.value" "new_value"
yaml_set() {
    _file="$1"
    _path="$2"
    _value="$3"
    yq eval -i "$_path = \"$_value\"" "$_file"
}

# Write a raw YAML value without quoting
# Usage: yaml_set_raw "file.yaml" ".path.to.value" "[]"
yaml_set_raw() {
    _file="$1"
    _path="$2"
    _value="$3"
    yq eval -i "$_path = $_value" "$_file"
}

# Append a value to a YAML array
# Usage: yaml_append "file.yaml" ".path.to.array" "new_item"
yaml_append() {
    _file="$1"
    _path="$2"
    _value="$3"
    yq eval -i "$_path += [\"$_value\"]" "$_file"
}

# Delete a YAML path
# Usage: yaml_delete "file.yaml" ".path.to.delete"
yaml_delete() {
    _file="$1"
    _path="$2"
    yq eval -i "del($_path)" "$_file"
}

# Return the keys of a YAML object, separated by newlines
# Usage: yaml_keys "file.yaml" ".path.to.object"
yaml_keys() {
    _file="$1"
    _path="${2:-.}"
    yq eval "$_path | keys | .[]" "$_file"
}

# Check whether a YAML path exists
# Usage: if yaml_has "file.yaml" ".path.to.check"; then ...
yaml_has() {
    _file="$1"
    _path="$2"
    _result=$(yq eval "$_path | . != null" "$_file")
    [ "$_result" = "true" ]
}

# Return the length of a YAML array
# Usage: yaml_array_len "file.yaml" ".path.to.array"
yaml_array_len() {
    _file="$1"
    _path="$2"
    yq eval "$_path | length" "$_file"
}

# Return a YAML array as a newline-separated string
# Usage: yaml_array_items "file.yaml" ".path.to.array"
yaml_array_items() {
    _file="$1"
    _path="$2"
    yq eval "$_path | .[]" "$_file"
}

# Merge two YAML files, with overlay taking precedence over base
# Usage: yaml_merge "base.yaml" "overlay.yaml" > "merged.yaml"
yaml_merge() {
    _base="$1"
    _overlay="$2"
    yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$_base" "$_overlay"
}

# Create a new YAML file
# Usage: yaml_create "file.yaml" "key" "value"
yaml_create() {
    _file="$1"
    _key="$2"
    _value="$3"
    echo "$_key: $_value" > "$_file"
}

# Create an empty YAML file
# Usage: yaml_create_empty "file.yaml"
yaml_create_empty() {
    _file="$1"
    echo "---" > "$_file"
}

# Helpers for reading feature information
# Usage: yaml_get_feature_name "manifest.yaml" "feature_key"
yaml_get_feature_name() {
    _file="$1"
    _feature="$2"
    URI_YAML_FEATURE="$_feature" yq eval '.features[strenv(URI_YAML_FEATURE)].name' "$_file"
}

yaml_get_feature_description() {
    _file="$1"
    _feature="$2"
    URI_YAML_FEATURE="$_feature" yq eval '.features[strenv(URI_YAML_FEATURE)].description' "$_file"
}

yaml_get_feature_dependencies() {
    _file="$1"
    _feature="$2"
    URI_YAML_FEATURE="$_feature" yq eval '(.features[strenv(URI_YAML_FEATURE)].dependencies // []) | .[]' "$_file"
}

yaml_get_feature_dev_dependencies() {
    _file="$1"
    _feature="$2"
    URI_YAML_FEATURE="$_feature" yq eval '(.features[strenv(URI_YAML_FEATURE)]."dev-dependencies" // []) | .[]' "$_file"
}

yaml_has_feature() {
    _yhf_file="$1"
    _yhf_feature="$2"
    _yhf_result=$(URI_YAML_FEATURE="$_yhf_feature" yq eval '.features[strenv(URI_YAML_FEATURE)] != null' "$_yhf_file")
    [ "$_yhf_result" = "true" ]
}

yaml_delete_feature() {
    _ydf_file="$1"
    _ydf_feature="$2"
    URI_YAML_FEATURE="$_ydf_feature" yq eval -i 'del(.features[strenv(URI_YAML_FEATURE)])' "$_ydf_file"
}

yaml_set_feature_empty() {
    _yse_file="$1"
    _yse_feature="$2"
    URI_YAML_FEATURE="$_yse_feature" yq eval -i '.features[strenv(URI_YAML_FEATURE)] = {}' "$_yse_file"
}

yaml_set_feature() {
    _ysf_file="$1"
    _ysf_feature="$2"
    _ysf_name="$3"
    _ysf_description="$4"
    _ysf_dependencies="$5"
    _ysf_dev_dependencies="$6"
    URI_YAML_FEATURE="$_ysf_feature" \
    URI_YAML_NAME="$_ysf_name" \
    URI_YAML_DESCRIPTION="$_ysf_description" \
    URI_YAML_DEPENDENCIES="$_ysf_dependencies" \
    URI_YAML_DEV_DEPENDENCIES="$_ysf_dev_dependencies" \
        yq eval -i '.features[strenv(URI_YAML_FEATURE)] = {
            "name": strenv(URI_YAML_NAME),
            "description": strenv(URI_YAML_DESCRIPTION),
            "dependencies": (strenv(URI_YAML_DEPENDENCIES) | from_yaml),
            "dev-dependencies": (strenv(URI_YAML_DEV_DEPENDENCIES) | from_yaml)
        }' "$_ysf_file"
}

# Return the feature list
# Usage: yaml_list_features "manifest.yaml"
yaml_list_features() {
    _file="$1"
    if yaml_has "$_file" ".features"; then
        yaml_keys "$_file" ".features"
    fi
}

# Read the inherits value
# Usage: yaml_get_inherits "manifest.yaml"
yaml_get_inherits() {
    _file="$1"
    _val=$(yaml_get "$_file" ".inherits")
    if [ "$_val" = "null" ]; then
        echo ""
    else
        echo "$_val"
    fi
}

# Read inherits as two neutral version axes.
# Preserve the object form; callers parse the string form using legacy rules.
yaml_inherits_type() {
    _yit_file="$1"
    yq eval '.inherits | tag' "$_yit_file"
}

yaml_get_inherits_upstream_version() {
    _yiu_file="$1"
    yq eval '.inherits."upstream-version" // ""' "$_yiu_file"
}

yaml_get_inherits_patchset_version() {
    _yip_file="$1"
    yq eval '.inherits."patchset-version" // ""' "$_yip_file"
}

# Validate root manifest settings and resolve values shared by all commands.
load_uri_config() {
    _luc_manifest="${URI_ROOT}/manifest.yaml"
    require_file "$_luc_manifest" "Could not find root manifest: $_luc_manifest"

    _luc_unknown=$(yq eval 'keys | map(select(. != "upstream" and . != "branch-prefix" and . != "committer")) | .[0] // ""' "$_luc_manifest")
    [ -z "$_luc_unknown" ] || die "Unknown root manifest setting: $_luc_unknown"

    _luc_upstream_tag=$(yq eval '.upstream | tag' "$_luc_manifest")
    URI_UPSTREAM=$(yq eval '.upstream // ""' "$_luc_manifest")
    if [ "$_luc_upstream_tag" != "!!str" ] || [ -z "$URI_UPSTREAM" ]; then
        die "The root manifest upstream must be a non-empty string."
    fi

    if yaml_has "$_luc_manifest" '."branch-prefix"'; then
        _luc_prefix_tag=$(yq eval '."branch-prefix" | tag' "$_luc_manifest")
        [ "$_luc_prefix_tag" = "!!str" ] || die "branch-prefix must be a string."
        URI_BRANCH_PREFIX=$(yq eval '."branch-prefix"' "$_luc_manifest")
    else
        URI_BRANCH_PREFIX="uri"
    fi
    validate_identifier "branch-prefix" "$URI_BRANCH_PREFIX"

    URI_COMMITTER_NAME=""
    URI_COMMITTER_EMAIL=""
    if ! yaml_has "$_luc_manifest" '.committer'; then
        URI_COMMITTER_MODE="legacy"
        URI_COMMITTER_NAME="URI"
        URI_COMMITTER_EMAIL="uri@uri.life"
    else
        _luc_committer_tag=$(yq eval '.committer | tag' "$_luc_manifest")
        [ "$_luc_committer_tag" = "!!map" ] || die "committer must be an object."
        URI_COMMITTER_MODE=$(yq eval '.committer.mode // ""' "$_luc_manifest")
        case "$URI_COMMITTER_MODE" in
            repository)
                _luc_committer_keys=$(yq eval '.committer | keys | map(select(. != "mode")) | .[0] // ""' "$_luc_manifest")
                [ -z "$_luc_committer_keys" ] || die "A repository committer may contain only mode."
                ;;
            explicit)
                _luc_committer_keys=$(yq eval '.committer | keys | map(select(. != "mode" and . != "name" and . != "email")) | .[0] // ""' "$_luc_manifest")
                [ -z "$_luc_committer_keys" ] || die "Unknown explicit committer setting: $_luc_committer_keys"
                URI_COMMITTER_NAME=$(yq eval '.committer.name // ""' "$_luc_manifest")
                URI_COMMITTER_EMAIL=$(yq eval '.committer.email // ""' "$_luc_manifest")
                _luc_name_tag=$(yq eval '.committer.name | tag' "$_luc_manifest")
                _luc_email_tag=$(yq eval '.committer.email | tag' "$_luc_manifest")
                if [ "$_luc_name_tag" != "!!str" ] || [ "$_luc_email_tag" != "!!str" ] || \
                    [ -z "$URI_COMMITTER_NAME" ] || [ -z "$URI_COMMITTER_EMAIL" ]; then
                    die "An explicit committer requires non-empty name and email values."
                fi
                ;;
            *)
                die "Unsupported committer mode: $URI_COMMITTER_MODE"
                ;;
        esac
    fi

    export URI_UPSTREAM URI_BRANCH_PREFIX URI_COMMITTER_MODE URI_COMMITTER_NAME URI_COMMITTER_EMAIL
}

# Check whether an excludes array is explicitly present
# Usage: if yaml_has_excludes "manifest.yaml"; then ...
yaml_has_excludes() {
    _yhe_file="$1"
    _yhe_result=$(yq eval 'has("excludes")' "$_yhe_file")
    [ "$_yhe_result" = "true" ]
}

# Validate the excludes schema
# A missing value is treated as an empty array; an explicit value must be an array of unique, non-empty strings.
yaml_validate_excludes() {
    _yve_file="$1"

    if ! yaml_has_excludes "$_yve_file"; then
        return 0
    fi

    _yve_tag=$(yq eval '.excludes | tag' "$_yve_file")
    if [ "$_yve_tag" != "!!seq" ]; then
        die "excludes must be an array of strings: feature <excludes> ($_yve_file)"
    fi

    _yve_invalid_count=$(yq eval '[.excludes[] | select(tag != "!!str" or test("^[[:space:]]*$"))] | length' "$_yve_file")
    if [ "$_yve_invalid_count" -ne 0 ]; then
        _yve_invalid=$(yq eval '[.excludes[] | select(tag != "!!str" or test("^[[:space:]]*$"))] | .[0] | to_json' "$_yve_file")
        die "excludes may contain only non-empty strings: feature $_yve_invalid ($_yve_file)"
    fi

    _yve_unique=$(yq eval '(.excludes | length) == (.excludes | unique | length)' "$_yve_file")
    if [ "$_yve_unique" != "true" ]; then
        _yve_duplicate=$(yq eval '.excludes | group_by(.) | map(select(length > 1) | .[0]) | .[0] // ""' "$_yve_file")
        die "excludes contains a duplicate feature: $_yve_duplicate ($_yve_file)"
    fi
}

# Return the excludes list
# Usage: yaml_list_excludes "manifest.yaml"
yaml_list_excludes() {
    _yle_file="$1"
    if yaml_has_excludes "$_yle_file"; then
        yq eval '.excludes[]' "$_yle_file"
    fi
}

# Check whether excludes contains a feature
# Usage: if yaml_excludes_feature "manifest.yaml" "feature"; then ...
yaml_excludes_feature() {
    _yef_file="$1"
    _yef_feature="$2"
    _yef_result=$(URI_YAML_VALUE="$_yef_feature" yq eval '(.excludes // []) | any_c(. == strenv(URI_YAML_VALUE))' "$_yef_file")
    [ "$_yef_result" = "true" ]
}

# Add a feature to excludes
yaml_append_exclude() {
    _yae_file="$1"
    _yae_feature="$2"
    URI_YAML_VALUE="$_yae_feature" yq eval -i '.excludes = ((.excludes // []) + [strenv(URI_YAML_VALUE)])' "$_yae_file"
}

# Remove a feature from excludes
yaml_remove_exclude() {
    _yre_file="$1"
    _yre_feature="$2"
    URI_YAML_VALUE="$_yre_feature" yq eval -i '.excludes = [.excludes[] | select(. != strenv(URI_YAML_VALUE))]' "$_yre_file"
}

# Return the complete feature object as JSON for debugging or processing
# Usage: yaml_get_features_json "manifest.yaml"
yaml_get_features_json() {
    _file="$1"
    yq eval '.features' -o=json "$_file"
}
