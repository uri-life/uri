#!/bin/sh
# graph_spec.sh - Tests for lib/commands/graph.sh

Describe 'lib/commands/graph.sh'
  Skip if "yq is not installed" has_no_yq

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"
  Include "$LIB_DIR/state.sh"
  Include "$LIB_DIR/commands/graph.sh"

  setup_patchset() {
    create_test_patchset "$TEST_TMPDIR"
    cd "$TEST_TMPDIR"
    URI_ROOT="$TEST_TMPDIR"
    export URI_ROOT
  }
  BeforeEach 'setup_patchset'

  Describe 'cmd_graph()'
    It 'prints the dependency graph in the default tree format'
      When call cmd_graph "v4.3.0" "uri1.0"
      The status should be success
      The output should include "base"
      The output should include "└─ custom_emoji"
      The output should include "theme"
    End

    It 'prints DOT format with --format dot'
      When call cmd_graph "v4.3.0" "uri1.0" "--format" "dot"
      The status should be success
      The output should include "digraph dependencies"
      The output should include '"base" -> "custom_emoji";'
    End

    It 'supports --format=dot'
      When call cmd_graph "v4.3.0" "uri1.0" "--format=dot"
      The status should be success
      The output should include "digraph dependencies"
    End

    It 'includes development dependencies with --include-dev'
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      yq eval -i '.features.dev_base = {"name": "Development Base", "description": "For development", "dependencies": []}' "$_manifest"
      yq eval -i '.features.custom_emoji."dev-dependencies" = ["dev_base"]' "$_manifest"

      When call cmd_graph "v4.3.0" "uri1.0" "--include-dev"
      The status should be success
      The output should include "dev_base"
      The output should include "custom_emoji"
    End

    It 'includes inherited features'
      create_test_inherited_patchset "$TEST_TMPDIR"
      When call cmd_graph "v4.3.0" "uri1.1"
      The status should be success
      The output should include "base"
      The output should include "extra"
    End

    It 'omits excluded inherited features from tree and DOT graphs'
      create_test_inherited_patchset "$TEST_TMPDIR"
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
      yaml_set_raw "$_manifest" ".excludes" '["theme"]'
      _tree=$(cmd_graph "v4.3.0" "uri1.1")
      _dot=$(cmd_graph "v4.3.0" "uri1.1" --format dot)
      When call printf '%s\n%s\n' "$_tree" "$_dot"
      The output should include "base"
      The output should include "extra"
      The output should not include "theme"
    End

    It 'fails for an unsupported format'
      When run script -e -c "
        URI_ROOT='$TEST_TMPDIR'; export URI_ROOT
        . '$LIB_DIR/common.sh'; . '$LIB_DIR/yaml.sh'; . '$LIB_DIR/git.sh'
        . '$LIB_DIR/topsort.sh'; . '$LIB_DIR/inherit.sh'; . '$LIB_DIR/state.sh'
        . '$LIB_DIR/commands/graph.sh'
        cmd_graph v4.3.0 uri1.0 --format json
      "
      The status should be failure
      The stderr should include 'Unsupported output format'
    End
  End

  Describe 'graph_usage()'
    It 'prints help'
      When call graph_usage
      The output should include "Usage"
      The output should include "uri graph"
      The output should include "--format"
    End
  End
End
