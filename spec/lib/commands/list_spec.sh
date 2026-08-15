#!/bin/sh
# list_spec.sh - Tests for lib/commands/list.sh

Describe 'lib/commands/list.sh'
  Skip if "yq is not installed" has_no_yq

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"
  Include "$LIB_DIR/state.sh"
  Include "$LIB_DIR/commands/init.sh"
  Include "$LIB_DIR/commands/add.sh"
  Include "$LIB_DIR/commands/list.sh"

  setup_patchset() {
    cd "$TEST_TMPDIR"
    cmd_init --upstream "https://github.com/mastodon/mastodon.git" "v4.3.0" >/dev/null 2>&1
    URI_ROOT="$TEST_TMPDIR"
    export URI_ROOT
    cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
    cmd_add "v4.3.0" "uri1.0" "base" --name "Base" >/dev/null 2>&1 || true
    cmd_add "v4.3.0" "uri1.0" "theme" --name "Theme" >/dev/null 2>&1 || true
  }
  BeforeEach 'setup_patchset'

  Describe 'upstream version list'
    It 'prints the version list'
      When call cmd_list
      The output should include "v4.3.0"
    End

    It 'prints all available versions'
      cmd_init "v4.4.0" >/dev/null 2>&1
      When call cmd_list
      The output should include "v4.3.0"
      The output should include "v4.4.0"
    End
  End

  Describe 'patchset list'
    It 'prints the patchset version list'
      When call cmd_list "v4.3.0"
      The output should include "uri1.0"
    End

    It 'prints a patchset without a uri prefix'
      cmd_add "v4.3.0" "patch1.0" >/dev/null
      When call cmd_list "v4.3.0"
      The output should include "patch1.0"
    End

    It 'does not print an invalid patchset directory'
      mkdir -p "$TEST_TMPDIR/versions/v4.3.0/patches/bad name"
      echo 'features: {}' > "$TEST_TMPDIR/versions/v4.3.0/patches/bad name/manifest.yaml"
      When call cmd_list "v4.3.0"
      The output should not include "bad name"
      The status should be success
    End
  End

  Describe 'feature list'
    It 'prints the feature list'
      When call cmd_list "v4.3.0" "uri1.0"
      The output should include "base"
      The output should include "theme"
    End

    It 'prints only active features after resolving inheritance'
      create_test_inherited_patchset "$TEST_TMPDIR"
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
      yaml_set_raw "$_manifest" ".excludes" '["theme"]'
      When call cmd_list "v4.3.0" "uri1.1"
      The output should include "base"
      The output should include "extra"
      The output should not include "theme"
    End
  End

  Describe 'list_usage()'
    It 'prints help'
      When call list_usage
      The output should include "Usage"
      The output should include "uri list"
    End
  End
End
