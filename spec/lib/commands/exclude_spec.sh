#!/bin/sh
# exclude_spec.sh - Tests for lib/commands/exclude.sh

Describe 'lib/commands/exclude.sh'
  Skip if "yq is not installed" has_no_yq

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"
  Include "$LIB_DIR/state.sh"
  Include "$LIB_DIR/commands/exclude.sh"

  setup_inherited() {
    cd "$TEST_TMPDIR"
    create_test_inherited_patchset "$TEST_TMPDIR"
    URI_ROOT="$TEST_TMPDIR"
    export URI_ROOT
    CHILD_MANIFEST="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
    PARENT_THEME_PATCH="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/theme.patch"
    export CHILD_MANIFEST PARENT_THEME_PATCH
  }
  BeforeEach 'setup_inherited'

  run_exclusion_command() {
    _rec_command="$1"
    shift
    ("$_rec_command" "$@")
  }

  Describe 'exclude'
    It 'excludes an active inherited feature'
      cmd_exclude "v4.3.0" "uri1.1" "theme" >/dev/null
      When call yaml_excludes_feature "$CHILD_MANIFEST" "theme"
      The status should be success
    End

    It 'does not change the inherited patch file'
      _before=$(cksum "$PARENT_THEME_PATCH")
      cmd_exclude "v4.3.0" "uri1.1" "theme" >/dev/null
      When call cksum "$PARENT_THEME_PATCH"
      The output should eq "$_before"
    End

    It 'rejects a feature declared by the current manifest'
      When call run_exclusion_command cmd_exclude "v4.3.0" "uri1.1" "extra"
      The status should be failure
      The stderr should include "uri remove"
    End

    It 'rejects a feature that is already excluded'
      cmd_exclude "v4.3.0" "uri1.1" "theme" >/dev/null
      When call run_exclusion_command cmd_exclude "v4.3.0" "uri1.1" "theme"
      The status should be failure
      The stderr should include "already excluded"
    End

    It 'rejects a nonexistent feature'
      When call run_exclusion_command cmd_exclude "v4.3.0" "uri1.1" "missing"
      The status should be failure
      The stderr should include "active inherited feature"
    End

    It 'does not change the manifest when exclusion would break a remaining feature dependency'
      _manifest_before=$(cksum "$CHILD_MANIFEST")
      _patch_before=$(cksum "$PARENT_THEME_PATCH")
      When call run_exclusion_command cmd_exclude "v4.3.0" "uri1.1" "base"
      The status should be failure
      The stderr should include 'extra.dependencies -> base'
      The value "$(cksum "$CHILD_MANIFEST")" should eq "$_manifest_before"
      The value "$(cksum "$PARENT_THEME_PATCH")" should eq "$_patch_before"
    End
  End

  Describe 'include'
    It 'removes an exclusion from the current manifest'
      cmd_exclude "v4.3.0" "uri1.1" "theme" >/dev/null
      cmd_include "v4.3.0" "uri1.1" "theme" >/dev/null
      When call yaml_excludes_feature "$CHILD_MANIFEST" "theme"
      The status should be failure
    End

    It 'rejects a feature not directly excluded by the current manifest'
      When call run_exclusion_command cmd_include "v4.3.0" "uri1.1" "theme"
      The status should be failure
      The stderr should include "not excluded by the current manifest"
    End

    It 'does not remove an exclusion from an ancestor manifest'
      yaml_set_raw "$CHILD_MANIFEST" ".excludes" '["theme"]'
      _grandchild_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.2"
      mkdir -p "$_grandchild_dir"
      printf 'inherits: uri1.1\nfeatures: {}\n' > "${_grandchild_dir}/manifest.yaml"
      When call run_exclusion_command cmd_include "v4.3.0" "uri1.2" "theme"
      The status should be failure
      The stderr should include "not excluded by the current manifest"
    End

    It 'does not change the manifest when removing an exclusion would break dependencies'
      _parent="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      yaml_set_raw "$_parent" ".features.dependent" '{"name": "Dependent", "description": "", "dependencies": ["base"]}'
      yaml_set_raw "$CHILD_MANIFEST" ".features" '{}'
      yaml_set_raw "$CHILD_MANIFEST" ".excludes" '["base", "dependent"]'
      When call run_exclusion_command cmd_include "v4.3.0" "uri1.1" "dependent"
      The status should be failure
      The stderr should include 'dependent.dependencies -> base'
      The contents of file "$CHILD_MANIFEST" should include "dependent"
    End
  End

  Describe 'usage'
    It 'prints exclude/include help'
      _exclude=$(exclude_usage)
      _include=$(include_usage)
      When call printf '%s\n%s\n' "$_exclude" "$_include"
      The output should include "uri exclude"
      The output should include "uri include"
    End
  End
End
