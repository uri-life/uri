#!/bin/sh
# state_spec.sh - Tests for lib/state.sh

Describe 'lib/state.sh'
  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/state.sh"

  Describe 'state_file()'
    It 'returns a state file path outside the repository'
      When call state_file "/tmp/repo"
      The output should match pattern "*/uri/state/*.state"
      The output should not include "/tmp/repo/.uri_state"
    End
  End

  Describe 'state_save() / state_get()'
    It 'stores and reads a key-value pair'
      state_save "$TEST_TMPDIR" "mykey" "myvalue"
      When call state_get "$TEST_TMPDIR" "mykey"
      The output should eq "myvalue"
    End

    It 'does not create .uri_state inside the repository'
      state_save "$TEST_TMPDIR" "mykey" "myvalue"
      When call test -f "${TEST_TMPDIR}/.uri_state"
      The status should be failure
    End

    It 'overwrites a value'
      state_save "$TEST_TMPDIR" "key" "old" || true
      state_save "$TEST_TMPDIR" "key" "new" || true
      When call state_get "$TEST_TMPDIR" "key"
      The output should eq "new"
    End

    It 'stores multiple keys'
      state_save "$TEST_TMPDIR" "a" "1"
      state_save "$TEST_TMPDIR" "b" "2"
      When call state_get "$TEST_TMPDIR" "a"
      The output should eq "1"
    End

    It 'allows spaces in a value'
      state_save "$TEST_TMPDIR" "spaced" "hello world"
      When call state_get "$TEST_TMPDIR" "spaced"
      The output should eq "hello world"
    End

    It 'returns an empty string for a nonexistent key'
      When call state_get "$TEST_TMPDIR" "nonexistent"
      The output should eq ""
    End
  End

  Describe 'state_delete()'
    It 'deletes a specific key'
      state_save "$TEST_TMPDIR" "delkey" "value" || true
      state_delete "$TEST_TMPDIR" "delkey" || true
      When call state_get "$TEST_TMPDIR" "delkey"
      The output should eq ""
    End

    It 'does not affect other keys'
      state_save "$TEST_TMPDIR" "keep" "kept"
      state_save "$TEST_TMPDIR" "remove" "gone"
      state_delete "$TEST_TMPDIR" "remove"
      When call state_get "$TEST_TMPDIR" "keep"
      The output should eq "kept"
    End
  End

  Describe 'state_clear()'
    It 'deletes the state file'
      state_save "$TEST_TMPDIR" "key" "val"
      state_clear "$TEST_TMPDIR"
      When call state_exists "$TEST_TMPDIR"
      The status should be failure
    End
  End

  Describe 'state_exists()'
    It 'returns true when the state file exists'
      state_save "$TEST_TMPDIR" "x" "y"
      When call state_exists "$TEST_TMPDIR"
      The status should be success
    End

    It 'returns false when the state file does not exist'
      When call state_exists "$TEST_TMPDIR"
      The status should be failure
    End
  End

  Describe 'state_in_progress()'
    It 'returns true when the operation key exists'
      state_save "$TEST_TMPDIR" "operation" "expand"
      When call state_in_progress "$TEST_TMPDIR"
      The status should be success
    End

    It 'returns false when the operation key does not exist'
      state_save "$TEST_TMPDIR" "other" "value"
      When call state_in_progress "$TEST_TMPDIR"
      The status should be failure
    End
  End

  Describe 'state_increment_index()'
    It 'increments the index by 1'
      state_save "$TEST_TMPDIR" "current_index" "3" || true
      state_increment_index "$TEST_TMPDIR" || true
      When call state_get "$TEST_TMPDIR" "current_index"
      The output should eq "4"
    End

    It 'starts at 0 and increments'
      state_save "$TEST_TMPDIR" "current_index" "0" || true
      state_increment_index "$TEST_TMPDIR" || true
      When call state_get "$TEST_TMPDIR" "current_index"
      The output should eq "1"
    End
  End

  Describe 'state_get_completed_features()'
    It 'returns features before the current index'
      state_save "$TEST_TMPDIR" "features" "a b c d"
      state_save "$TEST_TMPDIR" "current_index" "2"
      When call state_get_completed_features "$TEST_TMPDIR"
      The output should eq "a b"
    End

    It 'returns an empty result when the index is 0'
      state_save "$TEST_TMPDIR" "features" "a b c"
      state_save "$TEST_TMPDIR" "current_index" "0"
      When call state_get_completed_features "$TEST_TMPDIR"
      The output should eq ""
    End
  End

  Describe 'state_get_remaining_features()'
    It 'returns features starting at the current index'
      state_save "$TEST_TMPDIR" "features" "a b c d"
      state_save "$TEST_TMPDIR" "current_index" "2"
      When call state_get_remaining_features "$TEST_TMPDIR"
      The output should eq "c d"
    End

    It 'returns all features when the index is 0'
      state_save "$TEST_TMPDIR" "features" "a b c"
      state_save "$TEST_TMPDIR" "current_index" "0"
      When call state_get_remaining_features "$TEST_TMPDIR"
      The output should eq "a b c"
    End
  End

  Describe 'state_save_expand()'
    Skip if "git is not installed" has_no_git

    It 'stores expand state in one operation'
      REPO="${TEST_TMPDIR}/repo"
      create_test_git_repo "$REPO"
      state_save_expand "$REPO" "v4.3.0" "uri1.0" "base emoji" "0"
      When call state_get "$REPO" "operation"
      The output should eq "expand"
    End

    It 'stores neutral version keys and operation settings'
      REPO="${TEST_TMPDIR}/repo"
      create_test_git_repo "$REPO"
      URI_BRANCH_PREFIX="custom"
      URI_GIT_NAME="State User"
      URI_GIT_EMAIL="state@example.com"
      state_save_expand "$REPO" "v1.2.3" "patch1.0" "base" "0"
      _state_path=$(state_file "$REPO")
      When call state_get_patchset_version "$REPO"
      The output should eq "patch1.0"
      The contents of file "$_state_path" should include "branch_prefix=custom"
    End

    It 'restores the prefix and committer saved at operation start'
      REPO="${TEST_TMPDIR}/repo"
      create_test_git_repo "$REPO"
      URI_BRANCH_PREFIX="saved"
      URI_GIT_NAME="Saved User"
      URI_GIT_EMAIL="saved@example.com"
      state_save_expand "$REPO" "v1" "stack" "base" "0"
      URI_BRANCH_PREFIX="changed"
      URI_GIT_NAME="Changed User"
      URI_GIT_EMAIL="changed@example.com"
      state_restore_operation_config "$REPO"
      When call printf '%s:%s <%s>' "$URI_BRANCH_PREFIX" "$URI_GIT_NAME" "$URI_GIT_EMAIL"
      The output should eq 'saved:Saved User <saved@example.com>'
    End
  End

  Describe 'legacy state fallback'
    It 'continues to read mastodon_version and uri_version'
      state_save "$TEST_TMPDIR" "mastodon_version" "v4.5.16"
      state_save "$TEST_TMPDIR" "uri_version" "uri3.2"
      When call state_get_patchset_version "$TEST_TMPDIR"
      The output should eq "uri3.2"
    End
  End

  Describe 'state_save_collapse()'
    It 'stores collapse state in one operation'
      state_save_collapse "$TEST_TMPDIR" "v4.3.0" "uri1.0" "base emoji" "1"
      When call state_get "$TEST_TMPDIR" "operation"
      The output should eq "collapse"
    End

    It 'stores features'
      state_save_collapse "$TEST_TMPDIR" "v4.3.0" "uri1.0" "base emoji theme" "0"
      When call state_get "$TEST_TMPDIR" "features"
      The output should eq "base emoji theme"
    End
  End

  Describe 'state_show()'
    It 'prints information about the operation in progress'
      state_save "$TEST_TMPDIR" "operation" "expand"
      state_save "$TEST_TMPDIR" "mastodon_version" "v4.3.0"
      state_save "$TEST_TMPDIR" "uri_version" "uri1.0"
      state_save "$TEST_TMPDIR" "features" "base emoji"
      state_save "$TEST_TMPDIR" "current_index" "0"
      When call state_show "$TEST_TMPDIR"
      The output should include "expand"
      The output should include "v4.3.0"
    End

    It 'fails when the state file does not exist'
      When call state_show "$TEST_TMPDIR"
      The output should include "No operation is in progress"
      The status should be failure
    End
  End
End
