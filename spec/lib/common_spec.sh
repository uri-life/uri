#!/bin/sh
# common_spec.sh - Tests for lib/common.sh

Describe 'lib/common.sh'
  Include "$LIB_DIR/common.sh"

  Describe 'die()'
    It 'prints an error message to stderr and returns exit status 1'
      When run script -e -c ". '$LIB_DIR/common.sh'; die 'test error'"
      The status should be failure
      The stderr should include 'test error'
    End
  End

  Describe 'warn()'
    It 'prints a warning message to stderr'
      When call warn 'warning message'
      The stderr should include 'warning message'
    End
  End

  Describe 'info()'
    It 'prints an informational message to stdout'
      When call info 'informational message'
      The output should include 'informational message'
    End
  End

  Describe 'success()'
    It 'prints a success message to stdout'
      When call success 'success message'
      The output should include 'success message'
    End
  End

  Describe 'require_cmd()'
    It 'succeeds for an existing command'
      When call require_cmd "sh"
      The status should be success
    End

    It 'fails for a nonexistent command'
      When run script -e -c ". '$LIB_DIR/common.sh'; require_cmd 'nonexistent_cmd_xyz'"
      The status should be failure
      The stderr should include 'nonexistent_cmd_xyz'
    End
  End

  Describe 'upstream_version_dir()'
    It 'returns a version directory path based on URI_ROOT'
      URI_ROOT="/tmp/test"
      When call upstream_version_dir "v1.2.3+build"
      The output should eq "/tmp/test/versions/v1.2.3+build"
    End
  End

  Describe 'patchset_version_dir()'
    It 'returns a patchset version directory path based on URI_ROOT'
      URI_ROOT="/tmp/test"
      When call patchset_version_dir "v1.2.3+build" "stack-a"
      The output should eq "/tmp/test/versions/v1.2.3+build/patches/stack-a"
    End
  End

  Describe 'validate_identifier()'
    validate_identifier_safely() {
      (validate_identifier "$1" "$2")
    }

    It 'allows a safe identifier containing +._-'
      When call validate_identifier_safely "version" "v1.2.3+build-1"
      The status should be success
    End

    Parameters
      "slash" "bad/name"
      "space" "bad name"
      "double-dot" "bad..name"
      "lock" "bad.lock"
      "leading-dot" ".bad"
      "control" "bad	name"
    End
    It 'rejects an unsafe identifier: $1'
      When call validate_identifier_safely "identifier" "$2"
      The status should be failure
      The stderr should include 'Invalid'
    End
  End

  Describe 'resolve_path()'
    It 'returns the absolute path of a directory'
      When call resolve_path "$TEST_TMPDIR"
      The output should eq "$TEST_TMPDIR"
    End

    It 'returns the absolute path of a file'
      touch "${TEST_TMPDIR}/testfile"
      When call resolve_path "${TEST_TMPDIR}/testfile"
      The output should eq "${TEST_TMPDIR}/testfile"
    End

    It 'converts a relative path to an absolute path'
      When call resolve_path "."
      The output should not eq "."
      The output should start with "/"
    End
  End

  Describe 'find_uri_root()'
    It 'finds the directory containing manifest.yaml'
      touch "${TEST_TMPDIR}/manifest.yaml"
      mkdir -p "${TEST_TMPDIR}/subdir"
      cd "${TEST_TMPDIR}/subdir"
      When call find_uri_root
      The output should eq "$TEST_TMPDIR"
      The status should be success
    End

    It 'fails when manifest.yaml does not exist'
      cd "$TEST_TMPDIR"
      When call find_uri_root
      The status should be failure
    End
  End

  Describe 'require_uri_root()'
    It 'sets URI_ROOT when manifest.yaml exists'
      touch "${TEST_TMPDIR}/manifest.yaml"
      cd "$TEST_TMPDIR"
      When call require_uri_root
      The status should be success
      The variable URI_ROOT should eq "$TEST_TMPDIR"
    End
  End

  Describe 'set_uri_root_if_exists()'
    It 'succeeds when manifest.yaml exists'
      touch "${TEST_TMPDIR}/manifest.yaml"
      cd "$TEST_TMPDIR"
      When call set_uri_root_if_exists
      The status should be success
    End

    It 'fails without calling die when manifest.yaml does not exist'
      cd "$TEST_TMPDIR"
      When call set_uri_root_if_exists
      The status should be failure
    End
  End

  Describe 'require_file()'
    It 'succeeds when the file exists'
      touch "${TEST_TMPDIR}/exists.txt"
      When call require_file "${TEST_TMPDIR}/exists.txt"
      The status should be success
    End

    It 'calls die when the file does not exist'
      When run script -e -c ". '$LIB_DIR/common.sh'; require_file '${TEST_TMPDIR}/nofile.txt'"
      The status should be failure
      The stderr should include "File not found"
    End
  End

  Describe 'require_dir()'
    It 'succeeds when the directory exists'
      When call require_dir "$TEST_TMPDIR"
      The status should be success
    End

    It 'calls die when the directory does not exist'
      When run script -e -c ". '$LIB_DIR/common.sh'; require_dir '${TEST_TMPDIR}/nodir'"
      The status should be failure
      The stderr should include "Directory not found"
    End
  End

  Describe 'make_temp() / cleanup_temp()'
    It 'creates a temporary file'
      When call make_temp
      The output should not be blank
    End

    It 'deletes a temporary file with cleanup_temp'
      _tmpfile=$(mktemp)
      _TEMP_FILES="${_TEMP_FILES} ${_tmpfile}"
      echo "test" > "$_tmpfile"
      cleanup_temp
      When call test -f "$_tmpfile"
      The status should be failure
    End

    It 'creates a temporary directory and deletes it with cleanup_temp'
      make_temp_dir
      _tmpdir="$_made_temp_dir"
      test -d "$_tmpdir" || return 1
      cleanup_temp
      When call test -d "$_tmpdir"
      The status should be failure
    End
  End
End
