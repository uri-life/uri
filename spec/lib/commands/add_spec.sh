#!/bin/sh
# add_spec.sh - Tests for lib/commands/add.sh

Describe 'lib/commands/add.sh'
  Skip if "yq is not installed" has_no_yq

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"
  Include "$LIB_DIR/state.sh"
  Include "$LIB_DIR/commands/init.sh"
  Include "$LIB_DIR/commands/add.sh"

  setup_patchset() {
    cd "$TEST_TMPDIR"
    cmd_init --upstream "https://github.com/mastodon/mastodon.git" "v4.3.0" >/dev/null 2>&1
    URI_ROOT="$TEST_TMPDIR"
    export URI_ROOT
  }
  BeforeEach 'setup_patchset'

  Describe 'adding a patchset version'
    It 'adds a patchset version'
      When call cmd_add "v4.3.0" "uri1.0"
      The status should be success
      The output should include "uri1.0"
      The path "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0" should be directory
      The path "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml" should be exist
    End

    It 'creates a features section in manifest.yaml'
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      When call yaml_has "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml" ".features"
      The status should be success
    End

    It 'creates an empty excludes array in a new manifest.yaml'
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      When call yaml_array_len "$_manifest" ".excludes"
      The output should eq "0"
    End

    It 'sets inheritance with --inherits'
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.1" --inherits "uri1.0" >/dev/null 2>&1 || true
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
      When call yaml_get_inherits_patchset_version "$_manifest"
      The output should eq "uri1.0"
    End

    It 'records a patchset containing + in structured form with --inherits-upstream'
      cmd_init "v4.4.0" >/dev/null
      cmd_add "v4.3.0" "patch+base" >/dev/null
      cmd_add "v4.4.0" "patch1.1" --inherits "patch+base" --inherits-upstream "v4.3.0" >/dev/null
      _manifest="${TEST_TMPDIR}/versions/v4.4.0/patches/patch1.1/manifest.yaml"
      When call yq eval '.inherits."upstream-version" + ":" + .inherits."patchset-version"' "$_manifest"
      The output should eq "v4.3.0:patch+base"
    End

    It 'calls die for an existing patchset version'
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      When run script -e -c "
        URI_ROOT='$TEST_TMPDIR'; export URI_ROOT
        . '$LIB_DIR/common.sh'; . '$LIB_DIR/yaml.sh'; . '$LIB_DIR/git.sh'
        . '$LIB_DIR/topsort.sh'; . '$LIB_DIR/inherit.sh'; . '$LIB_DIR/state.sh'
        . '$LIB_DIR/commands/add.sh'
        cmd_add v4.3.0 uri1.0
      "
      The status should be failure
      The stderr should include 'already exists'
    End
  End

  Describe 'adding a feature'
    setup_patchset_version() {
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
    }
    BeforeEach 'setup_patchset_version'

    It 'adds a feature'
      When call cmd_add "v4.3.0" "uri1.0" "my_feature"
      The status should be success
      The output should include "my_feature"
    End

    It 'preserves a feature key containing + and .'
      cmd_add "v4.3.0" "uri1.0" "feature.v1+build" >/dev/null
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      When call yaml_has_feature "$_manifest" "feature.v1+build"
      The status should be success
      The path "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/feature.v1+build.patch" should be exist
    End

    It 'adds the feature to the manifest'
      cmd_add "v4.3.0" "uri1.0" "my_feature" >/dev/null 2>&1
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      When call yaml_has "$_manifest" ".features.my_feature"
      The status should be success
    End

    It 'creates an empty patch file'
      cmd_add "v4.3.0" "uri1.0" "my_feature" >/dev/null 2>&1 || true
      When call test -f "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/my_feature.patch"
      The status should be success
    End

    It 'sets the name with --name'
      cmd_add "v4.3.0" "uri1.0" "feat" --name "Test Feature" >/dev/null 2>&1 || true
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      When call yaml_get_feature_name "$_manifest" "feat"
      The output should eq "Test Feature"
    End

    It 'sets the description with --description'
      cmd_add "v4.3.0" "uri1.0" "feat" --description "Test description" >/dev/null 2>&1 || true
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      When call yaml_get_feature_description "$_manifest" "feat"
      The output should eq "Test description"
    End

    It 'sets dependencies with --dependencies'
      cmd_add "v4.3.0" "uri1.0" "base" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "feat" --dependencies "base" >/dev/null 2>&1 || true
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      When call yaml_get_feature_dependencies "$_manifest" "feat"
      The output should include "base"
    End

    It 'sets development dependencies with --dev-dependencies'
      cmd_add "v4.3.0" "uri1.0" "dev_base" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "feat" --dev-dependencies "dev_base" >/dev/null 2>&1 || true
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      When call yaml_get_feature_dev_dependencies "$_manifest" "feat"
      The output should include "dev_base"
    End

    It 'gives a new feature an empty development dependency array'
      cmd_add "v4.3.0" "uri1.0" "feat" >/dev/null 2>&1 || true
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      When call yaml_has "$_manifest" ".features.feat.\"dev-dependencies\""
      The status should be success
    End

    It 'calls die for a duplicate feature'
      cmd_add "v4.3.0" "uri1.0" "dup" >/dev/null 2>&1 || true
      When run script -e -c "
        URI_ROOT='$TEST_TMPDIR'; export URI_ROOT
        . '$LIB_DIR/common.sh'; . '$LIB_DIR/yaml.sh'; . '$LIB_DIR/git.sh'
        . '$LIB_DIR/topsort.sh'; . '$LIB_DIR/inherit.sh'; . '$LIB_DIR/state.sh'
        . '$LIB_DIR/commands/add.sh'
        cmd_add v4.3.0 uri1.0 dup
      "
      The status should be failure
      The stderr should include 'already exists'
    End
  End

  Describe 'add_usage()'
    It 'prints help'
      When call add_usage
      The output should include "Usage"
      The output should include "uri add"
    End
  End
End
