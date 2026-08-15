#!/bin/sh
# git_spec.sh - Tests for lib/git.sh

Describe 'lib/git.sh'
  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/git.sh"

  Describe 'pure string functions'
    Describe 'feature_branch_name()'
      It 'generates a feature branch name with the configured prefix'
        URI_BRANCH_PREFIX="custom"
        When call feature_branch_name "v1.2.3+build" "stack-a" "custom_emoji"
        The output should eq "custom/v1.2.3+build/stack-a/custom_emoji"
      End
    End

    Describe 'patchset_branch_name()'
      It 'generates a patchset branch name with the default prefix'
        unset URI_BRANCH_PREFIX
        When call patchset_branch_name "v1.2.3+build" "stack-a"
        The output should eq "uri/v1.2.3+build/stack-a"
      End
    End

    Describe 'normalize_git_url()'
      It 'normalizes SSH and HTTPS forms to the same remote'
        When call normalize_git_url "git@GitHub.COM:org/Repo.git"
        The output should eq "remote:github.com/org/Repo"
      End

      It 'removes credentials and the default port'
        When call normalize_git_url "https://user:secret@GitHub.COM:443/org/Repo.git/"
        The output should eq "remote:github.com/org/Repo"
      End

      It 'normalizes a relative local path and file URL to a canonical path'
        URI_ROOT="$TEST_TMPDIR"
        mkdir -p "$TEST_TMPDIR/source.git"
        _canonical_source=$(cd "$TEST_TMPDIR/source.git" && pwd -P)
        _canonical_source=${_canonical_source%.git}
        When call normalize_git_url "file://$TEST_TMPDIR/source.git"
        The output should eq "local:$_canonical_source"
      End
    End
  End

  Describe 'Git repository functions'
    Skip if "git is not installed" has_no_git

    setup_repo() {
      REPO_DIR="${TEST_TMPDIR}/repo"
      create_test_git_repo "$REPO_DIR"
    }
    BeforeEach 'setup_repo'

    Describe 'resolve_committer_identity()'
      It 'uses the target repository identity in repository mode'
        URI_COMMITTER_MODE="repository"
        When call resolve_committer_identity "$REPO_DIR"
        The variable URI_GIT_NAME should eq "Test"
        The variable URI_GIT_EMAIL should eq "test@example.com"
      End

      It 'uses the manifest identity in explicit mode'
        URI_COMMITTER_MODE="explicit"
        URI_COMMITTER_NAME="Patch Bot"
        URI_COMMITTER_EMAIL="patch@example.com"
        When call resolve_committer_identity "$REPO_DIR"
        The variable URI_GIT_NAME should eq "Patch Bot"
        The variable URI_GIT_EMAIL should eq "patch@example.com"
      End
    End

    Describe 'git_validate_origin()'
      validate_origin_safely() {
        (git_validate_origin "$1")
      }

      It 'accepts an HTTPS manifest and SCP origin for the same repository'
        URI_UPSTREAM="https://github.com/mastodon/mastodon.git"
        git -C "$REPO_DIR" remote set-url origin "git@GitHub.COM:mastodon/mastodon.git"
        When call git_validate_origin "$REPO_DIR"
        The status should be success
      End

      It 'compares a relative upstream and file origin against the manifest root'
        URI_ROOT="$TEST_TMPDIR"
        mkdir -p "$TEST_TMPDIR/local-source.git"
        URI_UPSTREAM="./local-source.git"
        git -C "$REPO_DIR" remote set-url origin "file://$TEST_TMPDIR/local-source.git"
        When call git_validate_origin "$REPO_DIR"
        The status should be success
      End

      It 'rejects a missing origin'
        URI_UPSTREAM="https://github.com/mastodon/mastodon.git"
        git -C "$REPO_DIR" remote remove origin
        When call validate_origin_safely "$REPO_DIR"
        The status should be failure
        The stderr should include 'no origin remote'
      End

      It 'rejects a repository path case mismatch'
        URI_UPSTREAM="https://github.com/Org/Repo.git"
        git -C "$REPO_DIR" remote set-url origin "https://github.com/org/repo.git"
        When call validate_origin_safely "$REPO_DIR"
        The status should be failure
        The stderr should include 'does not match'
      End
    End

    Describe 'git_is_repo()'
      It 'returns true for a Git repository'
        When call git_is_repo "$REPO_DIR"
        The status should be success
      End

      It 'returns false for a non-Git directory'
        When call git_is_repo "$TEST_TMPDIR"
        The status should be failure
      End
    End

    Describe 'git_require_repo()'
      It 'calls die for a non-Git directory'
        When run script -e -c ". '$LIB_DIR/common.sh'; . '$LIB_DIR/git.sh'; git_require_repo '$TEST_TMPDIR'"
        The status should be failure
        The stderr should include 'is not a Git repository'
      End
    End

    Describe 'git_is_clean()'
      It 'returns true for a clean working tree'
        When call git_is_clean "$REPO_DIR"
        The status should be success
      End

      It 'returns false when changes exist'
        echo "modified" >> "${REPO_DIR}/README.md"
        When call git_is_clean "$REPO_DIR"
        The status should be failure
      End
    End

    Describe 'git_ensure_clean()'
      It 'succeeds when clean'
        When call git_ensure_clean "$REPO_DIR"
        The status should be success
      End
    End

    Describe 'git_create_branch() / git_branch_exists()'
      It 'creates and verifies a branch'
        git_create_branch "$REPO_DIR" "test-branch"
        When call git_branch_exists "$REPO_DIR" "test-branch"
        The status should be success
      End
    End

    Describe 'git_create_branch_at()'
      It 'creates a branch without checking it out'
        git_create_branch_at "$REPO_DIR" "at-branch"
        When call git_current_branch "$REPO_DIR"
        The output should eq "main"
      End

      It 'finds the created branch'
        git_create_branch_at "$REPO_DIR" "at-branch2"
        When call git_branch_exists "$REPO_DIR" "at-branch2"
        The status should be success
      End
    End

    Describe 'git_checkout_branch()'
      It 'checks out a branch'
        git_create_branch_at "$REPO_DIR" "switch-branch"
        git_checkout_branch "$REPO_DIR" "switch-branch"
        When call git_current_branch "$REPO_DIR"
        The output should eq "switch-branch"
      End
    End

    Describe 'git_current_branch()'
      It 'returns the current branch name'
        When call git_current_branch "$REPO_DIR"
        The output should eq "main"
      End
    End

    Describe 'git_current_commit()'
      It 'returns the commit hash'
        When call git_current_commit "$REPO_DIR"
        The output should match pattern "[0-9a-f]*"
        The length of output should eq 40
      End
    End

    Describe 'git_branch_exists()'
      It 'returns false for a nonexistent branch'
        When call git_branch_exists "$REPO_DIR" "nonexistent"
        The status should be failure
      End
    End

    Describe 'git_detach_head()'
      It 'detaches HEAD'
        git_create_branch "$REPO_DIR" "detach-test"
        git_detach_head "$REPO_DIR"
        When call git_current_branch "$REPO_DIR"
        The output should eq "HEAD"
      End
    End

    Describe 'git_delete_branch()'
      It 'deletes a branch'
        git_create_branch_at "$REPO_DIR" "del-branch"
        git_delete_branch "$REPO_DIR" "del-branch"
        When call git_branch_exists "$REPO_DIR" "del-branch"
        The status should be failure
      End
    End

    Describe 'git_commit_count()'
      It 'returns the number of commits in a range'
        # Create an additional commit on main
        echo "extra" > "${REPO_DIR}/extra.txt"
        git -C "$REPO_DIR" add . >/dev/null 2>&1
        git -C "$REPO_DIR" commit -m "second" >/dev/null 2>&1
        _first=$(git -C "$REPO_DIR" rev-list --max-parents=0 HEAD)
        When call git_commit_count "$REPO_DIR" "${_first}..HEAD"
        The output should eq "1"
      End
    End

    Describe 'git_is_ancestor()'
      It 'returns true for an ancestor commit'
        _first=$(git -C "$REPO_DIR" rev-list --max-parents=0 HEAD)
        echo "descendant" > "${REPO_DIR}/descendant.txt"
        git -C "$REPO_DIR" add . >/dev/null 2>&1
        git -C "$REPO_DIR" commit -m "descendant" >/dev/null 2>&1
        When call git_is_ancestor "$REPO_DIR" "$_first" "HEAD"
        The status should be success
      End

      It 'returns false for a non-ancestor commit'
        git_create_branch_at "$REPO_DIR" "side" "HEAD"
        echo "main" > "${REPO_DIR}/main.txt"
        git -C "$REPO_DIR" add . >/dev/null 2>&1
        git -C "$REPO_DIR" commit -m "main change" >/dev/null 2>&1
        git_checkout_branch "$REPO_DIR" "side"
        echo "side" > "${REPO_DIR}/side.txt"
        git -C "$REPO_DIR" add . >/dev/null 2>&1
        git -C "$REPO_DIR" commit -m "side change" >/dev/null 2>&1
        When call git_is_ancestor "$REPO_DIR" "main" "side"
        The status should be failure
      End
    End

    Describe 'git_has_diff()'
      It 'finds no diff between identical refs'
        When call git_has_diff "$REPO_DIR" "HEAD" "HEAD"
        The status should be failure
      End

      It 'finds a diff between different refs'
        echo "change" > "${REPO_DIR}/new.txt"
        git -C "$REPO_DIR" add . >/dev/null 2>&1
        git -C "$REPO_DIR" commit -m "change" >/dev/null 2>&1
        _first=$(git -C "$REPO_DIR" rev-list --max-parents=0 HEAD)
        When call git_has_diff "$REPO_DIR" "$_first" "HEAD"
        The status should be success
      End
    End

    Describe 'git_am_in_progress()'
      It 'returns false when rebase-apply does not exist'
        When call git_am_in_progress "$REPO_DIR"
        The status should be failure
      End
    End

    Describe 'git_format_patch()'
      It 'extracts a patch and zero-pads the From hash'
        # Add a commit
        echo "patch-content" > "${REPO_DIR}/patched.txt"
        git -C "$REPO_DIR" add . >/dev/null 2>&1
        git -C "$REPO_DIR" commit -m "test patch" >/dev/null 2>&1
        _first=$(git -C "$REPO_DIR" rev-list --max-parents=0 HEAD)
        _output="${TEST_TMPDIR}/output.patch"
        When call git_format_patch "$REPO_DIR" "${_first}..HEAD" "$_output"
        The path "$_output" should be exist
        The contents of file "$_output" should include "patch-content"
        # Check that the hash in the From line was replaced with zeros
        The contents of file "$_output" should match pattern "*From 0000000*"
      End
    End

    Describe 'git_am()'
      It 'applies a patch'
        # Create a patch in the base repository
        echo "am-test" > "${REPO_DIR}/am-test.txt"
        git -C "$REPO_DIR" add . >/dev/null 2>&1
        git -C "$REPO_DIR" commit -m "am test commit" >/dev/null 2>&1
        _first=$(git -C "$REPO_DIR" rev-list --max-parents=0 HEAD)
        _patch="${TEST_TMPDIR}/am-test.patch"
        git -C "$REPO_DIR" format-patch --stdout "${_first}..HEAD" > "$_patch"

        # Apply it to another repository
        TARGET="${TEST_TMPDIR}/target"
        create_test_git_repo "$TARGET"
        When call git_am "$TARGET" "$_patch"
        The status should be success
        The output should include "Applying"
        The path "${TARGET}/am-test.txt" should be exist
      End
    End
  End
End
