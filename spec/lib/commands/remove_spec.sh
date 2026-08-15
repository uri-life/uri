#!/bin/sh
# remove_spec.sh - Tests for lib/commands/remove.sh

Describe 'lib/commands/remove.sh'
  Skip if "yq is not installed" has_no_yq

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"
  Include "$LIB_DIR/state.sh"
  Include "$LIB_DIR/commands/init.sh"
  Include "$LIB_DIR/commands/add.sh"
  Include "$LIB_DIR/commands/remove.sh"

  setup_with_features() {
    cd "$TEST_TMPDIR"
    cmd_init --upstream "https://github.com/mastodon/mastodon.git" "v4.3.0" >/dev/null 2>&1
    URI_ROOT="$TEST_TMPDIR"
    export URI_ROOT
    cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
    cmd_add "v4.3.0" "uri1.0" "base" >/dev/null 2>&1 || true
    cmd_add "v4.3.0" "uri1.0" "child" --dependencies "base" >/dev/null 2>&1 || true
    cmd_add "v4.3.0" "uri1.0" "independent" >/dev/null 2>&1 || true
  }
  BeforeEach 'setup_with_features'

  Describe 'removing a feature'
    It 'removes a feature with -f'
      cmd_remove "v4.3.0" "uri1.0" "independent" -f >/dev/null 2>&1 || true
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      When call yaml_has "$_manifest" ".features.independent"
      The status should be failure
    End

    It 'also deletes the patch file'
      cmd_remove "v4.3.0" "uri1.0" "independent" -f >/dev/null 2>&1 || true
      When call test -f "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/independent.patch"
      The status should be failure
    End

    It 'forces deletion with -f even when dependent features exist'
      When call cmd_remove "v4.3.0" "uri1.0" "base" -f
      The output should include "base"
      The stderr should include "depend on"
      The status should be success
    End
  End

  Describe 'removing a patchset version'
    It 'removes a patchset version with -f'
      cmd_remove "v4.3.0" "uri1.0" -f >/dev/null 2>&1 || true
      When call test -d "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0"
      The status should be failure
    End
  End

  Describe 'removing an upstream version'
    It 'removes an upstream version with -f'
      cmd_remove "v4.3.0" -f >/dev/null 2>&1 || true
      When call test -d "${TEST_TMPDIR}/versions/v4.3.0"
      The status should be failure
    End
  End

  Describe 'remove_usage()'
    It 'prints help'
      When call remove_usage
      The output should include "Usage"
      The output should include "uri remove"
    End
  End
End
