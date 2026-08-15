#!/bin/sh
# expand.sh - expand command implementation
# POSIX-compatible shell script

# Print expand command usage
expand_usage() {
    cat <<EOF
Usage: uri expand <upstream_version> <patchset_version> <feature> [destination] [options]
       uri expand <destination> --continue
       uri expand <destination> --abort

Apply a feature to the upstream source.

Arguments:
  upstream_version   Upstream tag or version (for example, v1.2.3+build)
  patchset_version   Patchset version (for example, stack-a)
  feature            Feature name (for example, custom_emoji)
  destination        Upstream Git repository path. When omitted, create a persistent full clone

Options:
  -h, --help         Print this help text
  --continue         Continue after resolving conflicts
  --abort            Abort the operation in progress and restore the previous state
  --force            Automatically delete the version branch created by a previous apply
  --no-dev           Apply without development dependencies

Examples:
  uri expand v1.2.3+build stack-a custom_emoji
  uri expand /path/to/project --continue
  uri expand /path/to/project --abort
EOF
}

# Main expand command function
cmd_expand() {
    STATE_OPERATION="expand"
    export STATE_OPERATION

    _upstream_version=""
    _patchset_version=""
    _feature=""
    _destination=""
    _continue=false
    _abort=false
    _force=false
    _include_dev=true

    # Collect options and positional arguments in one pass.
    _positional_count=0
    _positional_1=""
    _positional_2=""
    _positional_3=""
    _positional_4=""
    _positional_5=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                expand_usage
                exit 0
                ;;
            --continue)
                _continue=true
                ;;
            --abort)
                _abort=true
                ;;
            --force)
                _force=true
                ;;
            --no-dev)
                _include_dev=false
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
                    5) _positional_5="$1" ;;
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
        [ "$_positional_count" -le 4 ] || die "Too many arguments: $_positional_5"
        _upstream_version="$_positional_1"
        _patchset_version="$_positional_2"
        _feature="$_positional_3"
        _destination="$_positional_4"
    fi

    # Handle --continue
    if [ "$_continue" = true ]; then
        [ -n "$_destination" ] || die "--continue requires a destination."
        _destination=$(resolve_path "$_destination")
        git_require_repo "$_destination"
        _expand_continue "$_destination"
        return
    fi

    # Handle --abort
    if [ "$_abort" = true ]; then
        [ -n "$_destination" ] || die "--abort requires a destination."
        _destination=$(resolve_path "$_destination")
        git_require_repo "$_destination"
        _expand_abort "$_destination"
        return
    fi

    # Run a normal expand
    require_uri_root
    load_uri_config

    # Check required arguments
    if [ -z "$_upstream_version" ] || [ -z "$_patchset_version" ] || [ -z "$_feature" ]; then
        die "upstream_version, patchset_version, and feature are all required. See 'uri expand --help'."
    fi
    validate_identifier "upstream_version" "$_upstream_version"
    validate_identifier "patchset_version" "$_patchset_version"
    validate_identifier "feature" "$_feature"

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

    _expand_feature "$_upstream_version" "$_patchset_version" "$_feature" "$_destination" "$_force" "$_include_dev"
    print_preserved_clone "uri collapse '$_upstream_version' '$_patchset_version' '$_feature' '$_destination'"
}

# Main feature expansion logic (internal function)
_expand_feature() {
    _upstream_version="$1"
    _patchset_version="$2"
    _feature="$3"
    _dest="$4"
    _force="$5"
    _include_dev="${6:-true}"

    # Check the manifest
    _manifest=$(resolve_manifest_path "$_upstream_version" "$_patchset_version")
    require_file "$_manifest" "Could not find manifest: $_manifest"

    # Resolve inheritance and create a merged manifest
    _merged=$(resolve_inheritance "$_upstream_version" "$_patchset_version")

    # Check that the feature exists
    if ! yaml_has_feature "$_merged" "$_feature"; then
        die "Could not find feature: $_feature"
    fi

    # Create a sorted feature list including dependencies
    _sorted_features=$(get_feature_with_deps "$_merged" "$_feature" "$_include_dev")

    if [ -z "$_sorted_features" ]; then
        die "Failed to sort features"
    fi

    info "Features to apply (dependency order):"
    for _f in $_sorted_features; do
        echo "  - $_f"
    done

    # Check whether a version branch created by apply exists
    # The <prefix>/<upstream>/<patchset> form conflicts with feature branch paths
    _version_branch=$(patchset_branch_name "$_upstream_version" "$_patchset_version")
    if git_branch_exists "$_dest" "$_version_branch"; then
        if [ "$_force" = "true" ]; then
            warn "Deleting version branch '$_version_branch' (--force)..."
            _current=$(git_current_branch "$_dest")
            if [ "$_current" = "$_version_branch" ]; then
                git_detach_head "$_dest"
            fi
            git_delete_branch "$_dest" "$_version_branch"
        else
            die "Branch '$_version_branch' already exists (created by apply). Delete it with --force or manually: git branch -D $_version_branch"
        fi
    fi

    # Check whether the branch exists, indicating the feature is already expanded
    for _f in $_sorted_features; do
        _branch=$(feature_branch_name "$_upstream_version" "$_patchset_version" "$_f")
        if git_branch_exists "$_dest" "$_branch"; then
            die "Branch '$_branch' already exists. The previous expand operation has not been collapsed."
        fi
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

    # Save state
    state_save_expand "$_dest" "$_upstream_version" "$_patchset_version" "$_features_str" "0"

    # Apply in order
    _apply_features "$_dest" "$_upstream_version" "$_patchset_version" "$_features_str" "0"
}

# Apply features in order (internal function)
_apply_features() {
    _dest="$1"
    _upstream_version="$2"
    _patchset_version="$3"
    _features_str="$4"
    _start_index="$5"

    _index=0
    _prev_branch=""
    _last_branch=""

    for _feature in $_features_str; do
        # Skip entries before the starting index
        if [ "$_index" -lt "$_start_index" ]; then
            # Record the previous branch
            _prev_branch=$(feature_branch_name "$_upstream_version" "$_patchset_version" "$_feature")
            _index=$((_index + 1))
            continue
        fi

        info "[$_index] Applying feature '$_feature'..."

        # Save the current index
        state_save "$_dest" "current_index" "$_index"
        state_save "$_dest" "current_feature" "$_feature"

        # Find the patch file
        _patch_file=$(find_patch_file "$_upstream_version" "$_patchset_version" "$_feature" || true)

        if [ -z "$_patch_file" ] || [ ! -f "$_patch_file" ]; then
            warn "Could not find patch file: $_feature (skipping)"
            _index=$((_index + 1))
            continue
        fi

        # Create only a branch when the patch is empty
        if [ ! -s "$_patch_file" ]; then
            warn "Patch file is empty: $_feature (creating an empty branch)"
            _branch=$(feature_branch_name "$_upstream_version" "$_patchset_version" "$_feature")
            if git_branch_exists "$_dest" "$_branch"; then
                git_delete_branch "$_dest" "$_branch"
            fi
            git_create_branch_at "$_dest" "$_branch"
            _last_branch="$_branch"
            _index=$((_index + 1))
            continue
        fi

        # Apply the patch
        if ! git_am "$_dest" "$_patch_file"; then
            # A conflict occurred
            warn "A conflict occurred."
            echo ""
            echo "After resolving the conflict:"
            echo "  1. Edit the conflicting files"
            echo "  2. Stage them with git add <file>"
            echo "  3. Continue with 'uri expand $_dest --continue'"
            echo ""
            echo "To abort the operation: 'uri expand $_dest --abort'"
            print_preserved_clone "uri expand '$_dest' --continue"
            exit 1
        fi

        # Create a branch at the current HEAD without checking it out
        _branch=$(feature_branch_name "$_upstream_version" "$_patchset_version" "$_feature")
        if git_branch_exists "$_dest" "$_branch"; then
            git_delete_branch "$_dest" "$_branch"
        fi
        git_create_branch_at "$_dest" "$_branch"

        success "Applied feature '$_feature'"

        _last_branch="$_branch"
        _index=$((_index + 1))
    done

    # Check out the last feature branch
    if [ -n "$_last_branch" ]; then
        git_checkout_branch "$_dest" "$_last_branch"
    fi

    # Complete the operation and clear state
    state_clear "$_dest"
    success "Applied all features."
}

# Handle --continue (internal function)
_expand_continue() {
    _dest="$1"

    require_uri_root

    # Check state
    if ! state_in_progress "$_dest"; then
        die "No operation is in progress."
    fi

    _operation=$(state_get "$_dest" "operation")
    if [ "$_operation" != "expand" ]; then
        die "This is not an expand operation. Current operation: $_operation"
    fi
    state_restore_operation_config "$_dest"

    # Continue when git am is in progress
    if git_am_in_progress "$_dest"; then
        info "Continuing git am..."
        if ! git_am_continue "$_dest"; then
            die "git am --continue failed. Resolve conflicts first."
        fi
    fi

    # Create the current feature branch
    _upstream_version=$(state_get_upstream_version "$_dest")
    _patchset_version=$(state_get_patchset_version "$_dest")
    _current_feature=$(state_get "$_dest" "current_feature")

    _branch=$(feature_branch_name "$_upstream_version" "$_patchset_version" "$_current_feature")
    if git_branch_exists "$_dest" "$_branch"; then
        git_delete_branch "$_dest" "$_branch"
    fi
    git_create_branch_at "$_dest" "$_branch"

    success "Applied feature '$_current_feature'"

    # Advance to the next feature
    _features_str=$(state_get "$_dest" "features")
    _current_index=$(state_get "$_dest" "current_index")
    _next_index=$((_current_index + 1))

    # Apply the remaining features
    _apply_features "$_dest" "$_upstream_version" "$_patchset_version" "$_features_str" "$_next_index"
}

# Handle --abort (internal function)
_expand_abort() {
    _dest="$1"

    require_uri_root

    # Check state
    if ! state_in_progress "$_dest"; then
        die "No operation is in progress."
    fi

    _operation=$(state_get "$_dest" "operation")
    if [ "$_operation" != "expand" ]; then
        die "This is not an expand operation. Current operation: $_operation"
    fi

    info "Aborting expand operation..."

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

    success "Expand operation aborted."
}
