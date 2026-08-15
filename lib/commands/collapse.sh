#!/bin/sh
# collapse.sh - collapse command implementation
# POSIX-compatible shell script

# Print collapse command usage
collapse_usage() {
    cat <<EOF
Usage: uri collapse <upstream_version> <patchset_version> <feature> <source> [options]

Extract the specified feature from the upstream source into a patch file.
By default, reconstruct each dependent feature on its declared dependencies and check for changes.
After extraction, check out the tag and delete the related branches.

Arguments:
  upstream_version   Upstream tag or version (for example, v1.2.3+build)
  patchset_version   Patchset version (for example, stack-a)
  feature            Feature name (for example, custom_emoji)
  source             Upstream Git repository path

Options:
  --recursive        Update patches for the specified feature and all recursive dependencies
  -h, --help         Print this help text

Examples:
  uri collapse v4.3.2 uri1.23 custom_emoji /path/to/mastodon
  uri collapse v4.3.2 uri1.23 custom_emoji /path/to/mastodon --recursive
EOF
}

# Main collapse command function
cmd_collapse() {
    require_uri_root
    load_uri_config

    _upstream_version=""
    _patchset_version=""
    _feature=""
    _source=""
    _recursive=false

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                collapse_usage
                exit 0
                ;;
            --recursive)
                _recursive=true
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
                elif [ -z "$_source" ]; then
                    _source="$1"
                else
                    die "Too many arguments: $1"
                fi
                ;;
        esac
        shift
    done

    # Check required arguments
    if [ -z "$_upstream_version" ] || [ -z "$_patchset_version" ] || [ -z "$_feature" ] || [ -z "$_source" ]; then
        die "upstream_version, patchset_version, feature, and source are all required. See 'uri collapse --help'."
    fi
    validate_identifier "upstream_version" "$_upstream_version"
    validate_identifier "patchset_version" "$_patchset_version"
    validate_identifier "feature" "$_feature"

    _source=$(resolve_path "$_source")

    # Check the Git repository
    git_require_repo "$_source"
    git_validate_origin "$_source"
    resolve_committer_identity "$_source"

    # Check that the working tree is clean
    git_ensure_clean "$_source"

    _collapse_features "$_upstream_version" "$_patchset_version" "$_feature" "$_source" "$_recursive"
}

# Prepare all candidates in a temporary clone, then separate validation from persistence.
_collapse_features() {
    _cf_upstream_version="$1"
    _cf_patchset_version="$2"
    _cf_target="$3"
    _cf_source="$4"
    _cf_recursive="$5"

    _cf_patchset_dir=$(patchset_version_dir "$_cf_upstream_version" "$_cf_patchset_version")
    require_dir "$_cf_patchset_dir" "Could not find patchset version directory: $_cf_patchset_dir"
    _cf_manifest=$(resolve_manifest_path "$_cf_upstream_version" "$_cf_patchset_version")
    require_file "$_cf_manifest" "Could not find manifest: $_cf_manifest"
    _cf_merged=$(resolve_inheritance "$_cf_upstream_version" "$_cf_patchset_version")

    if ! yaml_has_feature "$_cf_merged" "$_cf_target"; then
        die "Could not find feature: $_cf_target"
    fi
    _cf_features=$(get_feature_with_deps_with_dev "$_cf_merged" "$_cf_target")
    [ -n "$_cf_features" ] || die "Failed to sort features"

    info "Features to collapse (dependency order):"
    for _cf_list_feature in $_cf_features; do
        echo "  - $_cf_list_feature"
    done

    _made_temp_dir=""
    make_temp_dir
    _cf_temp_root="$_made_temp_dir"
    _cf_clone="${_cf_temp_root}/source"
    _cf_candidates="${_cf_temp_root}/patches"
    mkdir -p "$_cf_candidates"

    info "Reconstructing patch candidates in a temporary Git clone..."
    if ! git clone --quiet --shared --no-checkout "$_cf_source" "$_cf_clone"; then
        _cleanup_temp_dir "$_cf_temp_root"
        die "Failed to create a temporary clone for collapse."
    fi
    git -C "$_cf_clone" config user.name "$URI_GIT_NAME"
    git -C "$_cf_clone" config user.email "$URI_GIT_EMAIL"
    git -C "$_cf_clone" config commit.gpgSign false

    if ! _prepare_collapse_candidates \
        "$_cf_upstream_version" "$_cf_patchset_version" "$_cf_merged" "$_cf_features" \
        "$_cf_clone" "$_cf_candidates"; then
        warn "Aborting collapse. Patches and source branches were not changed."
        _cleanup_temp_dir "$_cf_temp_root"
        return 1
    fi

    if [ "$_cf_recursive" = true ]; then
        _cf_to_save=$(echo "$_cf_features" | reverse_lines)
    else
        if ! _dependency_candidates_match \
            "$_cf_upstream_version" "$_cf_patchset_version" "$_cf_target" \
            "$_cf_features" "$_cf_candidates"; then
            _cleanup_temp_dir "$_cf_temp_root"
            return 1
        fi
        _cf_to_save="$_cf_target"
    fi

    _cf_saved=0
    _cf_skipped=0
    for _cf_save_feature in $_cf_to_save; do
        _cf_result=0
        _persist_collapse_candidate \
            "$_cf_upstream_version" "$_cf_patchset_version" "$_cf_save_feature" \
            "$_cf_candidates" || _cf_result=$?
        case $_cf_result in
            0) _cf_saved=$((_cf_saved + 1)) ;;
            1) _cf_skipped=$((_cf_skipped + 1)) ;;
            *) ;;
        esac
    done

    _cleanup_collapsed_branches \
        "$_cf_upstream_version" "$_cf_patchset_version" "$_cf_features" "$_cf_source"
    _cleanup_temp_dir "$_cf_temp_root"

    info "Result: ${_cf_saved} saved, ${_cf_skipped} skipped (identical to inherited patches)"
    success "Collapse complete."
}

# Rebase only each feature's unique commits onto its declared dependencies to create a candidate patch.
_prepare_collapse_candidates() {
    _pc_upstream_version="$1"
    _pc_patchset_version="$2"
    _pc_merged="$3"
    _pc_features="$4"
    _pc_clone="$5"
    _pc_candidates="$6"
    _pc_previous=""
    _pc_index=0

    if ! git -C "$_pc_clone" rev-parse --verify --quiet "refs/tags/${_pc_upstream_version}^{}" >/dev/null; then
        warn "Could not find upstream version tag: $_pc_upstream_version"
        return 1
    fi

    for _pc_feature in $_pc_features; do
        _pc_branch_name=$(feature_branch_name "$_pc_upstream_version" "$_pc_patchset_version" "$_pc_feature")
        _pc_source_ref="refs/remotes/origin/${_pc_branch_name}"
        if ! git -C "$_pc_clone" rev-parse --verify --quiet "${_pc_source_ref}^{commit}" >/dev/null; then
            warn "Could not find feature branch: $_pc_branch_name"
            return 1
        fi
        if ! git -C "$_pc_clone" merge-base --is-ancestor "$_pc_upstream_version" "$_pc_source_ref"; then
            warn "Feature branch does not descend from the version tag: $_pc_feature"
            return 1
        fi

        if [ -z "$_pc_previous" ]; then
            _pc_original_base="$_pc_upstream_version"
        else
            _pc_previous_ref="refs/remotes/origin/$(feature_branch_name "$_pc_upstream_version" "$_pc_patchset_version" "$_pc_previous")"
            _pc_original_base=$(git -C "$_pc_clone" merge-base "$_pc_previous_ref" "$_pc_source_ref") || {
                warn "Could not determine the merge base at the feature boundary: $_pc_feature"
                return 1
            }
        fi

        if ! git -C "$_pc_clone" checkout --detach --force "$_pc_upstream_version" >/dev/null 2>&1; then
            warn "Could not check out the version tag in the temporary clone."
            return 1
        fi

        _pc_required=$(get_feature_with_deps_with_dev "$_pc_merged" "$_pc_feature")
        for _pc_dependency in $_pc_required; do
            [ "$_pc_dependency" = "$_pc_feature" ] && continue
            _pc_dependency_patch="${_pc_candidates}/${_pc_dependency}.patch"
            if [ ! -f "$_pc_dependency_patch" ]; then
                warn "Could not find candidate patch for dependent feature: $_pc_dependency"
                return 1
            fi
            if [ -s "$_pc_dependency_patch" ] && ! git_am "$_pc_clone" "$_pc_dependency_patch" >/dev/null; then
                git_am_abort "$_pc_clone" || true
                warn "[$_pc_feature] Failed to apply dependent feature '$_pc_dependency'."
                return 1
            fi
        done
        _pc_dependency_base=$(git -C "$_pc_clone" rev-parse HEAD)

        _pc_candidate="${_pc_candidates}/${_pc_feature}.patch"
        _pc_commit_count=$(git_commit_count "$_pc_clone" "${_pc_original_base}..${_pc_source_ref}")
        if [ "$_pc_commit_count" -eq 0 ]; then
            : > "$_pc_candidate"
        else
            _pc_temp_branch="uri-collapse-candidate-${_pc_index}"
            if ! git -C "$_pc_clone" checkout -B "$_pc_temp_branch" "$_pc_source_ref" >/dev/null 2>&1; then
                warn "[$_pc_feature] Failed to create temporary branch."
                return 1
            fi
            if ! GIT_COMMITTER_NAME="$URI_GIT_NAME" GIT_COMMITTER_EMAIL="$URI_GIT_EMAIL" \
                git -C "$_pc_clone" rebase --onto "$_pc_dependency_base" "$_pc_original_base" "$_pc_temp_branch" >/dev/null 2>&1; then
                git -C "$_pc_clone" rebase --abort >/dev/null 2>&1 || true
                warn "[$_pc_feature] Failed to rebase onto the declared dependencies."
                return 1
            fi
            git_format_patch "$_pc_clone" "${_pc_dependency_base}..${_pc_temp_branch}" "$_pc_candidate"
            [ -s "$_pc_candidate" ] || {
                warn "[$_pc_feature] Patch candidate is empty."
                return 1
            }
        fi

        _pc_previous="$_pc_feature"
        _pc_index=$((_pc_index + 1))
    done
}

# In non-recursive mode, verify that dependent feature candidates match their current effective patches.
_dependency_candidates_match() {
    _dm_upstream_version="$1"
    _dm_patchset_version="$2"
    _dm_target="$3"
    _dm_features="$4"
    _dm_candidates="$5"
    _dm_changed=""

    for _dm_feature in $_dm_features; do
        [ "$_dm_feature" = "$_dm_target" ] && continue
        _dm_candidate="${_dm_candidates}/${_dm_feature}.patch"
        _dm_existing=$(find_patch_file "$_dm_upstream_version" "$_dm_patchset_version" "$_dm_feature" 2>/dev/null || true)
        if [ -z "$_dm_existing" ] || [ ! -f "$_dm_existing" ] || \
            ! _patches_are_equal "$_dm_candidate" "$_dm_existing"; then
            _dm_changed="$_dm_changed $_dm_feature"
        fi
    done

    if [ -n "$_dm_changed" ]; then
        warn "Detected dependent feature patch changes without --recursive:"
        for _dm_changed_feature in $_dm_changed; do
            echo "  - $_dm_changed_feature" >&2
        done
        warn "Collapse aborted. No patches or source branches were changed."
        warn "Use '--recursive' to update dependent features as well."
        return 1
    fi
}

# Returns: 0=saved, 1=identical to inherited patch, 2=empty patch
_persist_collapse_candidate() {
    _ps_upstream_version="$1"
    _ps_patchset_version="$2"
    _ps_feature="$3"
    _ps_candidates="$4"
    _ps_candidate="${_ps_candidates}/${_ps_feature}.patch"

    if [ ! -s "$_ps_candidate" ]; then
        warn "[$_ps_feature] No commits to extract."
        return 2
    fi

    _ps_inherited=$(_find_inherited_patch "$_ps_upstream_version" "$_ps_patchset_version" "$_ps_feature")
    if [ -n "$_ps_inherited" ] && [ -f "$_ps_inherited" ] && \
        _patches_are_equal "$_ps_candidate" "$_ps_inherited"; then
        info "[$_ps_feature] Identical to the inherited patch. Skipping."
        return 1
    fi

    _ps_patch_file="$(patchset_version_dir "$_ps_upstream_version" "$_ps_patchset_version")/${_ps_feature}.patch"
    if ! mv "$_ps_candidate" "$_ps_patch_file"; then
        warn "[$_ps_feature] Failed to save patch file: $_ps_patch_file"
        return 2
    fi
    success "[$_ps_feature] Extracted patch: $_ps_patch_file"
}

_cleanup_collapsed_branches() {
    _cb_upstream_version="$1"
    _cb_patchset_version="$2"
    _cb_features="$3"
    _cb_source="$4"

    git_checkout_tag "$_cb_source" "$_cb_upstream_version"
    info "Cleaning up branches..."
    _cb_reversed=$(echo "$_cb_features" | reverse_lines)
    for _cb_feature in $_cb_reversed; do
        _cb_branch=$(feature_branch_name "$_cb_upstream_version" "$_cb_patchset_version" "$_cb_feature")
        if git_branch_exists "$_cb_source" "$_cb_branch"; then
            git_delete_branch "$_cb_source" "$_cb_branch"
            info "  Deleted: $_cb_branch"
        fi
    done
}

# Find the parent's patch file in the inheritance chain, excluding the current version
# Usage: _find_inherited_patch "v4.3.2" "uri1.23" "feature"
_find_inherited_patch() {
    _upstream_version="$1"
    _patchset_version="$2"
    _feature="$3"

    _current_dir=$(patchset_version_dir "$_upstream_version" "$_patchset_version")

    # Search the inheritance chain for the patch file
    _chain=$(get_inheritance_chain "$_upstream_version" "$_patchset_version")

    for _manifest in $_chain; do
        _patch_dir=$(dirname "$_manifest")

        # Skip the current version
        if [ "$_patch_dir" = "$_current_dir" ]; then
            continue
        fi

        _patch_file="${_patch_dir}/${_feature}.patch"

        if [ -f "$_patch_file" ]; then
            echo "$_patch_file"
            return 0
        fi
    done

    # Return an empty string when no inherited patch exists
    echo ""
    return 0
}

# Compare two patch files, excluding metadata and comparing only the actual diff
# Usage: if _patches_are_equal "patch1" "patch2"; then ...
_patches_are_equal() {
    _patch1="$1"
    _patch2="$2"

    # Compare only the actual diff after excluding metadata lines
    # Excluded: From (commit hash), From: (author), Date:, Subject:, and index (blob hashes)
    _diff1=$(grep -v -E '^(From[ :]|Date:|Subject:|index )' "$_patch1")
    _diff2=$(grep -v -E '^(From[ :]|Date:|Subject:|index )' "$_patch2")

    [ "$_diff1" = "$_diff2" ]
}
