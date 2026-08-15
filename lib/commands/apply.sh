#!/bin/sh
# apply.sh - apply command implementation
# POSIX-compatible shell script

# Print apply command usage
apply_usage() {
    cat <<EOF
Usage: uri apply <upstream_version> <patchset_version> [destination] [options]
       uri apply <destination> --continue
       uri apply <destination> --abort

Apply all features in a patchset version.

Arguments:
  upstream_version   Upstream tag or version (for example, v1.2.3+build)
  patchset_version   Patchset version (for example, stack-a)
  destination        Upstream Git repository path. When omitted, create a persistent full clone

Options:
  -h, --help         Print this help text
  --continue         Continue after resolving conflicts
  --abort            Abort the operation in progress and restore the previous state

Description:
  Apply all features in the patchset version, including inherited features.
  This is primarily intended for deployment.

Examples:
  uri apply v1.2.3+build stack-a
  uri apply /path/to/project --continue
  uri apply /path/to/project --abort
EOF
}

# Main apply command function
cmd_apply() {
    STATE_OPERATION="apply"
    export STATE_OPERATION

    _upstream_version=""
    _patchset_version=""
    _destination=""
    _continue=false
    _abort=false

    # Collect options and positional arguments in one pass.
    _positional_count=0
    _positional_1=""
    _positional_2=""
    _positional_3=""
    _positional_4=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                apply_usage
                exit 0
                ;;
            --continue)
                _continue=true
                ;;
            --abort)
                _abort=true
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                _positional_count=$((_positional_count + 1))
                case "$_positional_count" in
                    1) _positional_1="$1" ;;
                    2) _positional_2="$1" ;;
                    3) _positional_3="$1" ;;
                    4) _positional_4="$1" ;;
                esac
                ;;
        esac
        shift
    done

    # Process positional arguments according to --continue or --abort mode
    if [ "$_continue" = true ] || [ "$_abort" = true ]; then
        [ "$_positional_count" -le 1 ] || die "Too many arguments: $_positional_2"
        _destination="$_positional_1"
    else
        [ "$_positional_count" -le 3 ] || die "Too many arguments: $_positional_4"
        _upstream_version="$_positional_1"
        _patchset_version="$_positional_2"
        _destination="$_positional_3"
    fi

    # Handle --continue using the same logic as expand
    if [ "$_continue" = true ]; then
        [ -n "$_destination" ] || die "--continue requires a destination."
        _destination=$(resolve_path "$_destination")
        git_require_repo "$_destination"
        _apply_continue "$_destination"
        return
    fi

    # Handle --abort using the same logic as expand
    if [ "$_abort" = true ]; then
        [ -n "$_destination" ] || die "--abort requires a destination."
        _destination=$(resolve_path "$_destination")
        git_require_repo "$_destination"
        _apply_abort "$_destination"
        return
    fi

    # Run a normal apply
    require_uri_root
    load_uri_config

    # Check required arguments
    if [ -z "$_upstream_version" ] || [ -z "$_patchset_version" ]; then
        die "upstream_version and patchset_version are required. See 'uri apply --help'."
    fi
    validate_identifier "upstream_version" "$_upstream_version"
    validate_identifier "patchset_version" "$_patchset_version"

    if [ -z "$_destination" ]; then
        clone_upstream_destination
        _destination="$URI_CLONED_DESTINATION"
    else
        _destination=$(resolve_path "$_destination")
    fi
    git_require_repo "$_destination"
    git_validate_origin "$_destination"
    resolve_committer_identity "$_destination"

    # Check for an operation in progress
    if state_in_progress "$_destination"; then
        state_show "$_destination"
        die "An operation is already in progress."
    fi

    # Check that the working tree is clean
    git_ensure_clean "$_destination"

    _apply_all_features "$_upstream_version" "$_patchset_version" "$_destination"
    print_preserved_clone "git -C '$_destination' status"
}

# Main logic for applying all features (internal function)
_apply_all_features() {
    _upstream_version="$1"
    _patchset_version="$2"
    _dest="$3"

    # Check the manifest
    _manifest=$(resolve_manifest_path "$_upstream_version" "$_patchset_version")
    require_file "$_manifest" "Could not find manifest: $_manifest"

    # Resolve inheritance and create a merged manifest
    _merged=$(resolve_inheritance "$_upstream_version" "$_patchset_version")

    # Sorted list of all features
    _sorted_features=$(get_sorted_apply_features "$_merged")

    if [ -z "$_sorted_features" ]; then
        warn "No features to apply."
        return
    fi

    info "Features to apply (dependency order):"
    for _f in $_sorted_features; do
        echo "  - $_f"
    done

    # Fetch tags, ignoring failures
    git_fetch_tags_quiet "$_dest"

    # Check out the upstream tag with detached HEAD
    git_checkout_tag "$_dest" "$_upstream_version"

    # Convert the feature list to a space-separated string
    _features_str=""
    for _f in $_sorted_features; do
        _features_str="$_features_str $_f"
    done
    _features_str=$(echo "$_features_str" | sed 's/^ *//')

    # Save state, identifying the operation as apply
    state_save "$_dest" "operation" "apply"
    state_save "$_dest" "upstream_version" "$_upstream_version"
    state_save "$_dest" "patchset_version" "$_patchset_version"
    state_save_operation_config "$_dest"
    state_save "$_dest" "features" "$_features_str"
    state_save "$_dest" "current_index" "0"
    state_save "$_dest" "start_commit" "$(git_current_commit "$_dest")"

    # Apply in order by reusing expand's _apply_features
    _apply_features_internal "$_dest" "$_upstream_version" "$_patchset_version" "$_features_str" "0" "ante"
}

# Apply features in order (internal function)
_apply_features_internal() {
    _dest="$1"
    _upstream_version="$2"
    _patchset_version="$3"
    _features_str="$4"
    _start_index="$5"
    _start_phase="${6:-ante}"

    _index=0

    for _feature in $_features_str; do
        # Skip entries before the starting index
        if [ "$_index" -lt "$_start_index" ]; then
            _index=$((_index + 1))
            continue
        fi

        # Save the current index
        state_save "$_dest" "current_index" "$_index"
        state_save "$_dest" "current_feature" "$_feature"

        _phase="ante"
        if [ "$_index" -eq "$_start_index" ]; then
            _phase="$_start_phase"
        fi

        if [ "$_phase" = "ante" ]; then
            info "[$_index] Applying feature '$_feature'..."
        fi

        # Find the patch file
        _patch_file=$(find_patch_file "$_upstream_version" "$_patchset_version" "$_feature" || true)

        if [ -z "$_patch_file" ] || [ ! -f "$_patch_file" ]; then
            warn "Could not find patch file: $_feature (skipping)"
            _index=$((_index + 1))
            continue
        fi

        # Skip an empty patch
        if [ ! -s "$_patch_file" ]; then
            warn "Patch file is empty: $_feature (skipping)"
            _index=$((_index + 1))
            continue
        fi

        if [ "$_phase" = "ante" ]; then
            if ! _apply_optional_phase_patch "$_dest" "$_upstream_version" "$_patchset_version" "$_feature" "ante"; then
                _apply_print_conflict_help "$_dest"
                exit 1
            fi
            _phase="main"
        fi

        if [ "$_phase" = "main" ]; then
            if ! _apply_main_patch "$_dest" "$_upstream_version" "$_patchset_version" "$_feature" "$_patch_file" "$_features_str" "$_index"; then
                _apply_print_conflict_help "$_dest"
                exit 1
            fi
            _phase="post"
        fi

        if [ "$_phase" = "post" ]; then
            if ! _apply_optional_phase_patch "$_dest" "$_upstream_version" "$_patchset_version" "$_feature" "post"; then
                _apply_print_conflict_help "$_dest"
                exit 1
            fi
        fi

        success "Applied feature '$_feature'"

        _index=$((_index + 1))
    done

    # Create and check out the single final branch after applying all features
    _branch=$(patchset_branch_name "$_upstream_version" "$_patchset_version")
    if git_branch_exists "$_dest" "$_branch"; then
        git_delete_branch "$_dest" "$_branch"
    fi
    git_create_branch "$_dest" "$_branch"

    # Complete the operation and clear state
    state_clear "$_dest"
    success "Applied all features. Branch: $_branch"
}

_apply_optional_phase_patch() {
    _dest="$1"
    _upstream_version="$2"
    _patchset_version="$3"
    _feature="$4"
    _phase="$5"

    case "$_phase" in
        ante)
            _phase_name="ANTE"
            _phase_patch=$(find_ante_patch "$_upstream_version" "$_patchset_version" "$_feature" || true)
            ;;
        post)
            _phase_name="POST"
            _phase_patch=$(find_post_patch "$_upstream_version" "$_patchset_version" "$_feature" || true)
            ;;
        *)
            die "Unknown apply phase: $_phase"
            ;;
    esac

    if [ -z "$_phase_patch" ]; then
        return 0
    fi

    if [ ! -s "$_phase_patch" ]; then
        warn "${_feature}~${_phase_name}.patch is empty (skipping)"
        return 0
    fi

    state_save "$_dest" "current_phase" "$_phase"
    info "  Applying ${_phase_name} patch: $(basename "$_phase_patch")"
    if ! git_am "$_dest" "$_phase_patch"; then
        warn "${_phase_name} patch conflict occurred."
        return 1
    fi
}

_apply_main_patch() {
    _dest="$1"
    _upstream_version="$2"
    _patchset_version="$3"
    _feature="$4"
    _patch_file="$5"
    _features_str="$6"
    _index="$7"

    state_save "$_dest" "current_phase" "main"

    if git_am "$_dest" "$_patch_file"; then
        return 0
    fi

    _pair_patch=$(find_applicable_pair_resolution_patch "$_upstream_version" "$_patchset_version" "$_feature" "$_features_str" "$_index" || true)
    if [ -z "$_pair_patch" ]; then
        warn "A conflict occurred."
        return 1
    fi

    info "  Applying conflict-resolution patch: $(basename "$_pair_patch")"
    if ! git_apply_resolution_patch "$_dest" "$_pair_patch"; then
        warn "Failed to apply conflict-resolution patch: $_pair_patch"
        return 1
    fi

    if ! git_am_continue "$_dest"; then
        warn "git am --continue failed after conflict resolution"
        return 1
    fi

    success "  Applied conflict-resolution patch"
}

_apply_print_conflict_help() {
    _dest="$1"

    echo ""
    echo "After resolving the conflict:"
    echo "  1. Edit the conflicting files"
    echo "  2. Stage them with git add <file>"
    echo "  3. Continue with 'uri apply $_dest --continue'"
    echo ""
    echo "To abort the operation: 'uri apply $_dest --abort'"
    print_preserved_clone "uri apply '$_dest' --continue"
}

# Handle --continue (internal function)
_apply_continue() {
    _dest="$1"

    require_uri_root

    # Check state
    if ! state_in_progress "$_dest"; then
        die "No operation is in progress."
    fi

    _operation=$(state_get "$_dest" "operation")
    if [ "$_operation" != "apply" ]; then
        die "This is not an apply operation. Current operation: $_operation"
    fi
    state_restore_operation_config "$_dest"

    # Continue when git am is in progress
    if git_am_in_progress "$_dest"; then
        info "Continuing git am..."
        if ! git_am_continue "$_dest"; then
            die "git am --continue failed. Resolve conflicts first."
        fi
    fi

    _upstream_version=$(state_get_upstream_version "$_dest")
    _patchset_version=$(state_get_patchset_version "$_dest")
    _features_str=$(state_get "$_dest" "features")
    _current_index=$(state_get "$_dest" "current_index")
    _current_phase=$(state_get "$_dest" "current_phase")

    case "$_current_phase" in
        ante)
            _resume_index="$_current_index"
            _resume_phase="main"
            ;;
        main|"")
            _resume_index="$_current_index"
            _resume_phase="post"
            ;;
        post)
            _current_feature=$(state_get "$_dest" "current_feature")
            success "Applied feature '$_current_feature'"
            _resume_index=$((_current_index + 1))
            _resume_phase="ante"
            ;;
        *)
            die "Unknown apply phase: $_current_phase"
            ;;
    esac

    # Apply the remaining features
    _apply_features_internal "$_dest" "$_upstream_version" "$_patchset_version" "$_features_str" "$_resume_index" "$_resume_phase"
}

# Handle --abort (internal function)
_apply_abort() {
    _dest="$1"

    require_uri_root

    # Check state
    if ! state_in_progress "$_dest"; then
        die "No operation is in progress."
    fi

    _operation=$(state_get "$_dest" "operation")
    if [ "$_operation" != "apply" ]; then
        die "This is not an apply operation. Current operation: $_operation"
    fi

    info "Aborting apply operation..."

    # Abort git am when it is in progress
    if git_am_in_progress "$_dest"; then
        git_am_abort "$_dest"
    fi

    # Return to the starting commit
    _start_commit=$(state_get "$_dest" "start_commit")
    if [ -n "$_start_commit" ]; then
        git -C "$_dest" reset --hard "$_start_commit" >/dev/null 2>&1
    fi

    # Clear state
    state_clear "$_dest"

    success "Apply operation aborted."
}
