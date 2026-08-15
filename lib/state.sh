#!/bin/sh
# state.sh - Operation state management utilities
# POSIX-compatible shell script
# Save and restore state when conflicts occur during expand/collapse

# State file directory, stored outside the target repository
STATE_DIR="${URI_STATE_DIR:-${TMPDIR:-/tmp}/uri/state}"

# Hash used to generate a state key
# Usage: state_hash "input"
state_hash() {
    _input="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$_input" | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$_input" | shasum -a 256 | awk '{print $1}'
    else
        printf '%s' "$_input" | cksum | awk '{print $1 "-" $2}'
    fi
}

# Create the state directory
_state_ensure_dir() {
    if [ ! -d "$STATE_DIR" ]; then
        mkdir -p "$STATE_DIR" || die "Failed to create state directory: $STATE_DIR"
        chmod 700 "$STATE_DIR" 2>/dev/null || true
    fi
}

# Resolve a path for state context
_state_resolve_repo() {
    _repo="$1"
    resolve_path "$_repo"
}

_state_resolve_uri_root() {
    if [ -n "${URI_ROOT:-}" ]; then
        resolve_path "$URI_ROOT"
    elif _root=$(find_uri_root 2>/dev/null); then
        resolve_path "$_root"
    else
        echo ""
    fi
}

# Return the full state file path
# Usage: state_file "/path/to/repo"
state_file() {
    _repo="$1"
    _repo_path=$(_state_resolve_repo "$_repo")
    _uri_root=$(_state_resolve_uri_root)
    _operation="${STATE_OPERATION:-default}"
    _hash=$(state_hash "${_uri_root}
${_repo_path}
${_operation}")
    echo "${STATE_DIR}/${_hash}.state"
}

# Check whether a state file belongs to the requested repository
_state_file_matches_repo() {
    _repo="$1"
    _state_file="$2"
    _repo_path=$(_state_resolve_repo "$_repo")

    [ -f "$_state_file" ] || return 1
    _stored_repo=$(grep "^repo_path=" "$_state_file" 2>/dev/null | cut -d'=' -f2-)
    [ "$_stored_repo" = "$_repo_path" ]
}

_state_ensure_file() {
    _repo="$1"
    _state_file=$(state_file "$_repo")
    _repo_path=$(_state_resolve_repo "$_repo")

    _state_ensure_dir

    if [ -f "$_state_file" ]; then
        if ! _state_file_matches_repo "$_repo" "$_state_file"; then
            die "State file collision detected: $_state_file"
        fi
    else
        {
            echo "repo_path=${_repo_path}"
            echo "uri_root=$(_state_resolve_uri_root)"
        } > "$_state_file"
        chmod 600 "$_state_file" 2>/dev/null || true
    fi

    echo "$_state_file"
}

# Save state
# Usage: state_save "/path/to/repo" "key" "value"
state_save() {
    _repo="$1"
    _key="$2"
    _value="$3"
    _state_file=$(_state_ensure_file "$_repo")

    # Remove an existing key
    if grep -q "^${_key}=" "$_state_file" 2>/dev/null; then
        _tmp=$(make_temp)
        grep -v "^${_key}=" "$_state_file" > "$_tmp"
        mv "$_tmp" "$_state_file"
    fi

    # Add the new value
    echo "${_key}=${_value}" >> "$_state_file"
}

# Read state
# Usage: state_get "/path/to/repo" "key"
state_get() {
    _repo="$1"
    _key="$2"
    _state_file=$(state_file "$_repo")

    if _state_file_matches_repo "$_repo" "$_state_file"; then
        grep "^${_key}=" "$_state_file" 2>/dev/null | cut -d'=' -f2-
    fi
}

# Delete a specific state key
# Usage: state_delete "/path/to/repo" "key"
state_delete() {
    _repo="$1"
    _key="$2"
    _state_file=$(state_file "$_repo")

    if _state_file_matches_repo "$_repo" "$_state_file"; then
        _tmp=$(make_temp)
        grep -v "^${_key}=" "$_state_file" > "$_tmp"
        mv "$_tmp" "$_state_file"
    fi
}

# Delete the entire state file
# Usage: state_clear "/path/to/repo"
state_clear() {
    _repo="$1"
    _state_file=$(state_file "$_repo")
    if _state_file_matches_repo "$_repo" "$_state_file"; then
        rm -f "$_state_file"
    fi
}

# Check whether a state file exists
# Usage: if state_exists "/path/to/repo"; then ...
state_exists() {
    _repo="$1"
    _state_file=$(state_file "$_repo")
    _state_file_matches_repo "$_repo" "$_state_file"
}

# Check for an operation in progress
# Usage: if state_in_progress "/path/to/repo"; then ...
state_in_progress() {
    _repo="$1"
    _operation=$(state_get "$_repo" "operation")
    [ -n "$_operation" ]
}

# Save expand state
# Usage: state_save_expand "/path/to/repo" "v4.3.2" "uri1.23" "feature1 feature2 feature3" "1"
state_save_expand() {
    _repo="$1"
    _upstream_version="$2"
    _patchset_version="$3"
    _features="$4"      # Space-separated feature list
    _current_index="$5" # Index of the feature currently being processed, starting at 0

    state_save "$_repo" "operation" "expand"
    state_save "$_repo" "upstream_version" "$_upstream_version"
    state_save "$_repo" "patchset_version" "$_patchset_version"
    state_save_operation_config "$_repo"
    state_save "$_repo" "features" "$_features"
    state_save "$_repo" "current_index" "$_current_index"
    state_save "$_repo" "start_commit" "$(git_current_commit "$_repo")"
}

# Save collapse state
# Usage: state_save_collapse "/path/to/repo" "v4.3.2" "uri1.23" "feature1 feature2" "1"
state_save_collapse() {
    _repo="$1"
    _upstream_version="$2"
    _patchset_version="$3"
    _features="$4"
    _current_index="$5"

    state_save "$_repo" "operation" "collapse"
    state_save "$_repo" "upstream_version" "$_upstream_version"
    state_save "$_repo" "patchset_version" "$_patchset_version"
    state_save_operation_config "$_repo"
    state_save "$_repo" "features" "$_features"
    state_save "$_repo" "current_index" "$_current_index"
}

state_save_operation_config() {
    _soc_repo="$1"
    state_save "$_soc_repo" "branch_prefix" "${URI_BRANCH_PREFIX:-uri}"
    state_save "$_soc_repo" "committer_name" "${URI_GIT_NAME:-URI}"
    state_save "$_soc_repo" "committer_email" "${URI_GIT_EMAIL:-uri@uri.life}"
}

state_get_upstream_version() {
    _sgu_repo="$1"
    _sgu_value=$(state_get "$_sgu_repo" "upstream_version")
    [ -n "$_sgu_value" ] || _sgu_value=$(state_get "$_sgu_repo" "mastodon_version")
    echo "$_sgu_value"
}

state_get_patchset_version() {
    _sgp_repo="$1"
    _sgp_value=$(state_get "$_sgp_repo" "patchset_version")
    [ -n "$_sgp_value" ] || _sgp_value=$(state_get "$_sgp_repo" "uri_version")
    echo "$_sgp_value"
}

state_restore_operation_config() {
    _src_repo="$1"
    URI_BRANCH_PREFIX=$(state_get "$_src_repo" "branch_prefix")
    [ -n "$URI_BRANCH_PREFIX" ] || URI_BRANCH_PREFIX="uri"
    export URI_BRANCH_PREFIX
    restore_committer_identity_from_state "$_src_repo"
}

# Print the current operation state for the user
# Usage: state_show "/path/to/repo"
state_show() {
    _repo="$1"
    _state_file=$(state_file "$_repo")

    if ! _state_file_matches_repo "$_repo" "$_state_file"; then
        info "No operation is in progress."
        return 1
    fi

    _operation=$(state_get "$_repo" "operation")
    _upstream_version=$(state_get_upstream_version "$_repo")
    _patchset_version=$(state_get_patchset_version "$_repo")
    _features=$(state_get "$_repo" "features")
    _current_index=$(state_get "$_repo" "current_index")

    # Determine the current feature
    _count=0
    _current_feature=""
    for _f in $_features; do
        if [ "$_count" -eq "$_current_index" ]; then
            _current_feature="$_f"
            break
        fi
        _count=$((_count + 1))
    done

    echo "Operation in progress:"
    echo "  Operation: $_operation"
    echo "  Upstream version: $_upstream_version"
    echo "  Patchset version: $_patchset_version"
    echo "  Current feature: $_current_feature ($((_current_index + 1))/$(echo "$_features" | wc -w | tr -d ' '))"
    echo ""
    echo "After resolving the conflict:"
    echo "  Continue with: uri $_operation --continue"
    echo "  Abort with: uri $_operation --abort"
}

# Return the processed feature list up to the current index
# Usage: state_get_completed_features "/path/to/repo"
state_get_completed_features() {
    _repo="$1"
    _features=$(state_get "$_repo" "features")
    _current_index=$(state_get "$_repo" "current_index")

    _count=0
    _completed=""
    for _f in $_features; do
        if [ "$_count" -lt "$_current_index" ]; then
            _completed="$_completed $_f"
        fi
        _count=$((_count + 1))
    done

    echo "$_completed" | sed 's/^ *//'
}

# Return the remaining feature list starting at the current index
# Usage: state_get_remaining_features "/path/to/repo"
state_get_remaining_features() {
    _repo="$1"
    _features=$(state_get "$_repo" "features")
    _current_index=$(state_get "$_repo" "current_index")

    _count=0
    _remaining=""
    for _f in $_features; do
        if [ "$_count" -ge "$_current_index" ]; then
            _remaining="$_remaining $_f"
        fi
        _count=$((_count + 1))
    done

    echo "$_remaining" | sed 's/^ *//'
}

# Increment the current index
# Usage: state_increment_index "/path/to/repo"
state_increment_index() {
    _repo="$1"
    _current=$(state_get "$_repo" "current_index")
    _new=$((_current + 1))
    state_save "$_repo" "current_index" "$_new"
}
