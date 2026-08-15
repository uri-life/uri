#!/bin/sh
# init_spec.sh - Tests for lib/commands/init.sh

Describe 'lib/commands/init.sh'
  Skip if "yq is not installed" has_no_yq

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"
  Include "$LIB_DIR/state.sh"
  Include "$LIB_DIR/commands/init.sh"

  Describe 'cmd_init()'
    It 'initializes a patch set'
      cd "$TEST_TMPDIR"
      When call cmd_init --upstream "https://example.com/project.git"
      The status should be success
      The output should include "Initialized"
      The path "${TEST_TMPDIR}/manifest.yaml" should be exist
      The path "${TEST_TMPDIR}/versions" should be directory
    End

    It 'includes upstream in manifest.yaml'
      cd "$TEST_TMPDIR"
      cmd_init --upstream "https://example.com/project.git" >/dev/null 2>&1
      When call cat "${TEST_TMPDIR}/manifest.yaml"
      The output should include "upstream:"
    End

    It 'specifies the upstream URL with --upstream'
      cd "$TEST_TMPDIR"
      cmd_init --upstream "https://custom.git" >/dev/null 2>&1
      When call cat "${TEST_TMPDIR}/manifest.yaml"
      The output should include "https://custom.git"
    End

    It 'fails when --upstream is omitted for a new root'
      cd "$TEST_TMPDIR"
      When run script -e -c "
        . '$LIB_DIR/common.sh'; . '$LIB_DIR/yaml.sh'; . '$LIB_DIR/git.sh'
        . '$LIB_DIR/commands/init.sh'
        cmd_init
      "
      The status should be failure
      The stderr should include 'requires --upstream URL'
      The path "${TEST_TMPDIR}/manifest.yaml" should not be exist
    End

    It 'records the default branch prefix and repository committer in a new root'
      cd "$TEST_TMPDIR"
      cmd_init --upstream "https://example.com/project.git" >/dev/null
      When call yq eval '."branch-prefix" + ":" + .committer.mode' "${TEST_TMPDIR}/manifest.yaml"
      The output should eq "uri:repository"
    End

    It 'records an explicit committer identity'
      cd "$TEST_TMPDIR"
      cmd_init --upstream "https://example.com/project.git" \
        --committer-name "Patch Bot" --committer-email "patch@example.com" >/dev/null
      When call yq eval '.committer.mode + ":" + .committer.name + ":" + .committer.email' "${TEST_TMPDIR}/manifest.yaml"
      The output should eq "explicit:Patch Bot:patch@example.com"
    End

    It 'rejects changes to existing root settings'
      cd "$TEST_TMPDIR"
      cmd_init --upstream "https://example.com/project.git" >/dev/null
      When run script -e -c "
        cd '$TEST_TMPDIR'
        . '$LIB_DIR/common.sh'; . '$LIB_DIR/yaml.sh'; . '$LIB_DIR/git.sh'
        . '$LIB_DIR/commands/init.sh'
        cmd_init --upstream https://other.example/project.git v2
      "
      The status should be failure
      The stderr should include 'upstream setting cannot be changed'
      The path "${TEST_TMPDIR}/versions/v2" should not be exist
    End

    It 'initializes with an upstream version'
      cd "$TEST_TMPDIR"
      When call cmd_init --upstream "https://example.com/project.git" "v4.3.0"
      The status should be success
      The output should include "Initialized"
      The path "${TEST_TMPDIR}/versions/v4.3.0" should be directory
      The path "${TEST_TMPDIR}/versions/v4.3.0/patches" should be directory
    End

    It 'adds a new version to an initialized root'
      cd "$TEST_TMPDIR"
      cmd_init --upstream "https://example.com/project.git" "v4.3.0" >/dev/null 2>&1
      When call cmd_init "v4.4.0"
      The status should be success
      The output should include "v4.4.0"
      The path "${TEST_TMPDIR}/versions/v4.4.0" should be directory
    End

    It 'calls die when run without a version in an initialized root'
      cd "$TEST_TMPDIR"
      cmd_init --upstream "https://example.com/project.git" >/dev/null 2>&1
      When run script -e -c "
        cd '$TEST_TMPDIR'
        . '$LIB_DIR/common.sh'
        . '$LIB_DIR/yaml.sh'
        . '$LIB_DIR/git.sh'
        . '$LIB_DIR/topsort.sh'
        . '$LIB_DIR/inherit.sh'
        . '$LIB_DIR/state.sh'
        . '$LIB_DIR/commands/init.sh'
        cmd_init
      "
      The status should be failure
      The stderr should include 'Already initialized'
    End
  End

  Describe 'init_usage()'
    It 'prints help'
      When call init_usage
      The output should include "Usage"
      The output should include "uri init"
    End
  End
End
