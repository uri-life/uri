#!/bin/sh
# git.sh - Git utility functions
# POSIX-compatible shell script

# Identity used when creating commits. Legacy values are used until the root manifest is loaded.
URI_GIT_NAME="URI"
URI_GIT_EMAIL="uri@uri.life"

# Resolve the manifest's committer policy for the target repository.
resolve_committer_identity() {
    _rci_repo="$1"
    case "${URI_COMMITTER_MODE:-legacy}" in
        repository)
            URI_GIT_NAME=$(git -C "$_rci_repo" config --get user.name 2>/dev/null || true)
            URI_GIT_EMAIL=$(git -C "$_rci_repo" config --get user.email 2>/dev/null || true)
            if [ -z "$URI_GIT_NAME" ] || [ -z "$URI_GIT_EMAIL" ]; then
                die "Git user.name and user.email are required in the target repository: $_rci_repo"
            fi
            ;;
        explicit|legacy)
            URI_GIT_NAME="$URI_COMMITTER_NAME"
            URI_GIT_EMAIL="$URI_COMMITTER_EMAIL"
            ;;
        *)
            die "Unsupported committer mode: ${URI_COMMITTER_MODE:-}"
            ;;
    esac
    case "${URI_GIT_NAME}${URI_GIT_EMAIL}" in
        *'
'*|*''*)
            die "The committer name and email must each be a single line."
            ;;
    esac
    export URI_GIT_NAME URI_GIT_EMAIL
}

# Restore the identity saved in state. Use the fixed URI identity for legacy state.
restore_committer_identity_from_state() {
    _rcs_repo="$1"
    URI_GIT_NAME=$(state_get "$_rcs_repo" "committer_name")
    URI_GIT_EMAIL=$(state_get "$_rcs_repo" "committer_email")
    [ -n "$URI_GIT_NAME" ] || URI_GIT_NAME="URI"
    [ -n "$URI_GIT_EMAIL" ] || URI_GIT_EMAIL="uri@uri.life"
    export URI_GIT_NAME URI_GIT_EMAIL
}

# Check whether a directory is a Git repository
# Usage: git_is_repo "/path/to/dir"
git_is_repo() {
    _dir="$1"
    git -C "$_dir" rev-parse --git-dir >/dev/null 2>&1
}

# Require a Git repository
# Usage: git_require_repo "/path/to/dir"
git_require_repo() {
    _dir="$1"
    if ! git_is_repo "$_dir"; then
        die "$_dir is not a Git repository."
    fi
}

# Check whether the working tree is clean (staged and modified files only; ignore untracked files)
# Usage: if git_is_clean "/path/to/repo"; then ...
git_is_clean() {
    _dir="$1"
    _status=$(git -C "$_dir" status --porcelain --untracked-files=no 2>/dev/null)
    [ -z "$_status" ]
}

# Require a clean working tree
# Usage: git_ensure_clean "/path/to/repo"
git_ensure_clean() {
    _dir="$1"
    if ! git_is_clean "$_dir"; then
        die "The working tree has uncommitted changes. Commit or stash them first."
    fi
}

# Check out a tag
# Usage: git_checkout_tag "/path/to/repo" "v4.3.2"
git_checkout_tag() {
    _dir="$1"
    _tag="$2"
    info "Checking out tag $_tag..."
    git -C "$_dir" checkout "$_tag" >/dev/null 2>&1 || die "Could not find tag $_tag."
}

# Create and check out a branch
# Usage: git_create_branch "/path/to/repo" "branch-name"
git_create_branch() {
    _dir="$1"
    _branch="$2"
    git -C "$_dir" checkout -b "$_branch" >/dev/null 2>&1 || die "Failed to create branch $_branch"
}

# Create a branch without checking it out
# Usage: git_create_branch_at "/path/to/repo" "branch-name" ["commit"]
git_create_branch_at() {
    _dir="$1"
    _branch="$2"
    _commit="${3:-HEAD}"
    git -C "$_dir" branch "$_branch" "$_commit" >/dev/null 2>&1 || die "Failed to create branch $_branch"
}

# Check out a branch
# Usage: git_checkout_branch "/path/to/repo" "branch-name"
git_checkout_branch() {
    _dir="$1"
    _branch="$2"
    git -C "$_dir" checkout "$_branch" >/dev/null 2>&1 || die "Failed to check out branch $_branch"
}

# Check whether a branch exists
# Usage: if git_branch_exists "/path/to/repo" "branch-name"; then ...
git_branch_exists() {
    _dir="$1"
    _branch="$2"
    git -C "$_dir" show-ref --verify --quiet "refs/heads/$_branch"
}

# Return the current branch name
# Usage: git_current_branch "/path/to/repo"
git_current_branch() {
    _dir="$1"
    git -C "$_dir" rev-parse --abbrev-ref HEAD 2>/dev/null
}

# Return the current commit hash
# Usage: git_current_commit "/path/to/repo"
git_current_commit() {
    _dir="$1"
    git -C "$_dir" rev-parse HEAD 2>/dev/null
}

# Apply a patch with git am
# Usage: git_am "/path/to/repo" "/path/to/patch.patch"
# Returns: 0=success, 1=conflict
git_am() {
    _dir="$1"
    _patch="$2"
    if GIT_COMMITTER_NAME="$URI_GIT_NAME" GIT_COMMITTER_EMAIL="$URI_GIT_EMAIL" \
       git -C "$_dir" am --3way --no-gpg-sign < "$_patch" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Continue applying a patch after resolving conflicts
# Usage: git_am_continue "/path/to/repo"
git_am_continue() {
    _dir="$1"
    GIT_COMMITTER_NAME="$URI_GIT_NAME" GIT_COMMITTER_EMAIL="$URI_GIT_EMAIL" \
    git -C "$_dir" am --continue --no-gpg-sign
}

# Apply a resolution patch to a conflicting git am worktree and stage the affected files
# Usage: git_apply_resolution_patch "/path/to/repo" "/path/to/resolution.patch"
git_apply_resolution_patch() {
    _dir="$1"
    _patch="$2"
    _paths=$(make_temp)
    _sorted_paths=$(make_temp)
    _numstat=$(make_temp)

    git -C "$_dir" diff --name-only --diff-filter=U > "$_paths"
    if ! git -C "$_dir" apply --numstat "$_patch" > "$_numstat"; then
        return 1
    fi
    awk '{print $3}' "$_numstat" >> "$_paths"

    if ! git -C "$_dir" apply --whitespace=nowarn "$_patch"; then
        return 1
    fi

    sort -u "$_paths" > "$_sorted_paths"
    while IFS= read -r _path; do
        if [ -n "$_path" ]; then
            git -C "$_dir" add -- "$_path" || return 1
        fi
    done < "$_sorted_paths"
}

# Abort patch application and restore the previous state
# Usage: git_am_abort "/path/to/repo"
git_am_abort() {
    _dir="$1"
    git -C "$_dir" am --abort 2>/dev/null
}

# Check whether git am is in progress
# Usage: if git_am_in_progress "/path/to/repo"; then ...
git_am_in_progress() {
    _dir="$1"
    [ -d "$_dir/.git/rebase-apply" ]
}

# Extract a patch with git format-patch
# Usage: git_format_patch "/path/to/repo" "commit_range" "/path/to/output.patch"
# Note: the hash in the "From <hash>" line is replaced with zeros to avoid unnecessary diffs from commit hash changes
git_format_patch() {
    _dir="$1"
    _range="$2"
    _output="$3"
    # --binary: encode binary files in base64 and include them in the patch
    # --no-signature: remove Git version information for consistent output across environments
    # --no-stat: remove the diffstat header for a cleaner patch
    # After creating the patch, replace the hash in the "From <hash>" line with zeros of the same length
    git -C "$_dir" format-patch --binary --no-signature --no-stat --stdout "$_range" | \
        awk '/^From [0-9a-f]+ Mon Sep 17 00:00:00 2001$/ {
            gsub(/[0-9a-f]/, "0", $2)
        } { print }' > "$_output"
}

# Return the number of commits in a commit range
# Usage: git_commit_count "/path/to/repo" "range"
git_commit_count() {
    _dir="$1"
    _range="$2"
    git -C "$_dir" rev-list --count "$_range" 2>/dev/null || echo "0"
}

# Check the ancestry relationship between commits or branches
# Usage: if git_is_ancestor "/path/to/repo" "ancestor" "descendant"; then ...
git_is_ancestor() {
    _dir="$1"
    _ancestor="$2"
    _descendant="$3"
    git -C "$_dir" merge-base --is-ancestor "$_ancestor" "$_descendant" 2>/dev/null
}

# Detach HEAD from the current branch
# Usage: git_detach_head "/path/to/repo"
git_detach_head() {
    _dir="$1"
    git -C "$_dir" checkout --detach HEAD >/dev/null 2>&1
}

# Delete a branch
# Usage: git_delete_branch "/path/to/repo" "branch-name"
git_delete_branch() {
    _dir="$1"
    _branch="$2"
    git -C "$_dir" branch -D "$_branch" >/dev/null 2>&1
}

# Fetch from the remote repository
# Usage: git_fetch "/path/to/repo"
git_fetch() {
    _dir="$1"
    git -C "$_dir" fetch --all --tags >/dev/null 2>&1
}

# Fetch tags only, ignoring failures
# Usage: git_fetch_tags_quiet "/path/to/repo"
git_fetch_tags_quiet() {
    _dir="$1"
    git -C "$_dir" fetch --tags >/dev/null 2>&1 || true
}

# Normalize a Git URL into a comparable remote or local representation.
normalize_git_url() {
    _ngu_url="$1"
    _ngu_scheme=""

    case "$_ngu_url" in
        file://*)
            _ngu_path=${_ngu_url#file://}
            case "$_ngu_path" in
                localhost/*) _ngu_path=/${_ngu_path#localhost/} ;;
            esac
            _normalize_local_git_path "$_ngu_path"
            return
            ;;
        *://*)
            _ngu_scheme=${_ngu_url%%://*}
            _ngu_rest=${_ngu_url#*://}
            _ngu_authority=${_ngu_rest%%/*}
            if [ "$_ngu_authority" = "$_ngu_rest" ]; then
                _ngu_path=""
            else
                _ngu_path=${_ngu_rest#*/}
            fi
            _ngu_host=${_ngu_authority##*@}
            case "$_ngu_scheme:$_ngu_host" in
                https:*:443) _ngu_host=${_ngu_host%:443} ;;
                http:*:80) _ngu_host=${_ngu_host%:80} ;;
                ssh:*:22) _ngu_host=${_ngu_host%:22} ;;
            esac
            _ngu_host=$(printf '%s' "$_ngu_host" | tr '[:upper:]' '[:lower:]')
            _ngu_path=${_ngu_path%/}
            _ngu_path=${_ngu_path%.git}
            printf 'remote:%s/%s\n' "$_ngu_host" "$_ngu_path"
            return
            ;;
        /*|./*|../*)
            _normalize_local_git_path "$_ngu_url"
            return
            ;;
        *@*:*|[A-Za-z0-9.-]*:*)
            _ngu_authority=${_ngu_url%%:*}
            _ngu_path=${_ngu_url#*:}
            _ngu_host=${_ngu_authority##*@}
            _ngu_host=$(printf '%s' "$_ngu_host" | tr '[:upper:]' '[:lower:]')
            _ngu_path=${_ngu_path%/}
            _ngu_path=${_ngu_path%.git}
            printf 'remote:%s/%s\n' "$_ngu_host" "$_ngu_path"
            return
            ;;
        *)
            _normalize_local_git_path "$_ngu_url"
            ;;
    esac
}

_normalize_local_git_path() {
    _nlg_path="$1"
    case "$_nlg_path" in
        /*) ;;
        *) _nlg_path="${URI_ROOT}/${_nlg_path}" ;;
    esac
    _nlg_path=${_nlg_path%/}
    _nlg_dir=$(dirname "$_nlg_path")
    _nlg_base=$(basename "$_nlg_path")
    if [ -d "$_nlg_path" ]; then
        _nlg_canonical=$(cd "$_nlg_path" 2>/dev/null && pwd -P) || die "Could not resolve local upstream path: $_nlg_path"
    elif [ -d "$_nlg_dir" ]; then
        _nlg_canonical="$(cd "$_nlg_dir" 2>/dev/null && pwd -P)/$_nlg_base"
    else
        die "Could not resolve local upstream path: $_nlg_path"
    fi
    _nlg_canonical=${_nlg_canonical%.git}
    printf 'local:%s\n' "$_nlg_canonical"
}

git_validate_origin() {
    _gvo_repo="$1"
    _gvo_origin=$(git -C "$_gvo_repo" remote get-url origin 2>/dev/null || true)
    [ -n "$_gvo_origin" ] || die "The target repository has no origin remote: $_gvo_repo"
    _gvo_expected=$(normalize_git_url "$URI_UPSTREAM")
    _gvo_actual=$(normalize_git_url "$_gvo_origin")
    if [ "$_gvo_expected" != "$_gvo_actual" ]; then
        die "The origin does not match the manifest upstream: $_gvo_origin"
    fi
}

# Create a persistent full clone for use when destination is omitted.
clone_upstream_destination() {
    _cud_root=$(mktemp -d "${TMPDIR:-/tmp}/uri-clone.XXXXXX") || die "Failed to create a temporary clone directory"
    _cud_name=${URI_UPSTREAM%/}
    _cud_name=${_cud_name##*/}
    _cud_name=${_cud_name##*:}
    _cud_name=${_cud_name%.git}
    [ -n "$_cud_name" ] || _cud_name="upstream"
    URI_CLONED_DESTINATION="${_cud_root}/${_cud_name}"
    info "Creating a full clone of the upstream: $URI_CLONED_DESTINATION"
    if ! git clone "$URI_UPSTREAM" "$URI_CLONED_DESTINATION"; then
        warn "Preserving clone: $URI_CLONED_DESTINATION"
        die "Failed to clone the upstream"
    fi
    export URI_CLONED_DESTINATION
    info "Automatically created destination: $URI_CLONED_DESTINATION"
}

print_preserved_clone() {
    _ppc_followup="$1"
    if [ -n "${URI_CLONED_DESTINATION:-}" ]; then
        echo ""
        info "Preserved automatic clone: $URI_CLONED_DESTINATION"
        [ -z "$_ppc_followup" ] || echo "Next command: $_ppc_followup"
    fi
}

# Generate a feature branch name for expand/collapse
feature_branch_name() {
    _fbn_upstream_version="$1"
    _fbn_patchset_version="$2"
    _fbn_feature="$3"
    _fbn_branch="${URI_BRANCH_PREFIX:-uri}/${_fbn_upstream_version}/${_fbn_patchset_version}/${_fbn_feature}"
    validate_branch_ref "$_fbn_branch"
    echo "$_fbn_branch"
}

# Generate a patchset branch name for apply
patchset_branch_name() {
    _pbn_upstream_version="$1"
    _pbn_patchset_version="$2"
    _pbn_branch="${URI_BRANCH_PREFIX:-uri}/${_pbn_upstream_version}/${_pbn_patchset_version}"
    validate_branch_ref "$_pbn_branch"
    echo "$_pbn_branch"
}

# Base branches are no longer used; tags serve directly as the base

# Check whether two branches or commits differ
# Usage: if git_has_diff "/path/to/repo" "ref1" "ref2"; then ...
git_has_diff() {
    _dir="$1"
    _ref1="$2"
    _ref2="$3"
    ! git -C "$_dir" diff --quiet "$_ref1" "$_ref2" 2>/dev/null
}
