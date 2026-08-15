#!/bin/sh
# expand_spec.sh - Tests for lib/commands/expand.sh

Describe 'lib/commands/expand.sh'
  Skip if "yq is not installed" has_no_yq
  Skip if "git is not installed" has_no_git

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"
  Include "$LIB_DIR/state.sh"
  Include "$LIB_DIR/commands/init.sh"
  Include "$LIB_DIR/commands/add.sh"
  Include "$LIB_DIR/commands/expand.sh"

  Describe 'expand_usage()'
    It 'prints help'
      When call expand_usage
      The output should include "Usage"
      The output should include "uri expand"
    End
  End

  Describe 'cmd_expand()'
    run_expand_command() {
      (cmd_expand "$@")
    }

    setup_expand_env() {
      # Create a patch set
      cd "$TEST_TMPDIR" || return 1
      cmd_init --upstream "https://github.com/mastodon/mastodon.git" "v4.3.0" >/dev/null 2>&1
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "base" >/dev/null 2>&1 || true

      # Create and tag a Git repository
      UPSTREAM_DIR="${TEST_TMPDIR}/mastodon"
      export UPSTREAM_DIR
      mkdir -p "$UPSTREAM_DIR"
      git init -b main "$UPSTREAM_DIR" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" config user.email "test@example.com"
      git -C "$UPSTREAM_DIR" config user.name "Test"
      git -C "$UPSTREAM_DIR" config tag.gpgSign false
      git -C "$UPSTREAM_DIR" config commit.gpgSign false
      git -C "$UPSTREAM_DIR" remote add origin "$UPSTREAM_DIR"
      yaml_set "$TEST_TMPDIR/manifest.yaml" ".upstream" "$UPSTREAM_DIR"
      echo "initial" > "${UPSTREAM_DIR}/README.md"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Initial commit" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" tag "v4.3.0"

      # Create a real patch for the base feature
      echo "hello" > "${UPSTREAM_DIR}/hello.txt"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add hello" >/dev/null 2>&1

      # Ensure the patch directory exists and extract the patch
      _patch_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0"
      mkdir -p "$_patch_dir"
      git -C "$UPSTREAM_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/base.patch"

      # Reset to the tag
      git -C "$UPSTREAM_DIR" checkout -b temp_for_reset "v4.3.0" >/dev/null 2>&1
    }
    BeforeEach 'setup_expand_env'

    It 'applies a feature to the upstream source'
      When call cmd_expand "v4.3.0" "uri1.0" "base" "$UPSTREAM_DIR"
      The status should be success
      The output should include "Applied"
      The path "${UPSTREAM_DIR}/hello.txt" should be exist
    End

    It 'creates a feature branch'
      cmd_expand "v4.3.0" "uri1.0" "base" "$UPSTREAM_DIR" >/dev/null 2>&1 || true
      When call git_branch_exists "$UPSTREAM_DIR" "uri/v4.3.0/uri1.0/base"
      The status should be success
    End

    It 'creates a checkpoint branch for an empty patch'
      cmd_add "v4.3.0" "uri1.0" "empty" >/dev/null 2>&1 || true
      cmd_expand "v4.3.0" "uri1.0" "empty" "$UPSTREAM_DIR" >/dev/null 2>&1 || true
      When call git_branch_exists "$UPSTREAM_DIR" "uri/v4.3.0/uri1.0/empty"
      The status should be success
    End

    It 'clears the state file after completion'
      cmd_expand "v4.3.0" "uri1.0" "base" "$UPSTREAM_DIR" >/dev/null 2>&1 || true
      When call state_exists "$UPSTREAM_DIR"
      The status should be failure
    End

    It 'does not apply an excluded inherited feature'
      cmd_add "v4.3.0" "uri1.1" --inherits "uri1.0" >/dev/null
      _child_manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
      yaml_append_exclude "$_child_manifest" "base"
      When call run_expand_command "v4.3.0" "uri1.1" "base" "$UPSTREAM_DIR"
      The status should be failure
      The stderr should include "Could not find feature: base"
      The path "${UPSTREAM_DIR}/hello.txt" should not be exist
    End
  End

  Describe 'development dependencies'
    setup_expand_dev_env() {
      cd "$TEST_TMPDIR" || return 1
      cmd_init --upstream "https://github.com/mastodon/mastodon.git" "v4.3.0" >/dev/null 2>&1
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "dev_base" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "feature" --dev-dependencies "dev_base" >/dev/null 2>&1 || true

      UPSTREAM_DIR="${TEST_TMPDIR}/mastodon"
      export UPSTREAM_DIR
      mkdir -p "$UPSTREAM_DIR"
      git init -b main "$UPSTREAM_DIR" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" config user.email "test@example.com"
      git -C "$UPSTREAM_DIR" config user.name "Test"
      git -C "$UPSTREAM_DIR" config tag.gpgSign false
      git -C "$UPSTREAM_DIR" config commit.gpgSign false
      git -C "$UPSTREAM_DIR" remote add origin "$UPSTREAM_DIR"
      yaml_set "$TEST_TMPDIR/manifest.yaml" ".upstream" "$UPSTREAM_DIR"
      echo "initial" > "${UPSTREAM_DIR}/README.md"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Initial commit" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" tag "v4.3.0"

      _patch_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0"

      echo "dev" > "${UPSTREAM_DIR}/dev.txt"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add dev dependency" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/dev_base.patch"

      git -C "$UPSTREAM_DIR" checkout -b feature_patch "v4.3.0" >/dev/null 2>&1
      echo "feature" > "${UPSTREAM_DIR}/feature.txt"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add feature" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/feature.patch"

      git -C "$UPSTREAM_DIR" checkout -b ready_branch "v4.3.0" >/dev/null 2>&1
    }
    BeforeEach 'setup_expand_dev_env'

    It 'includes development dependencies by default'
      When call cmd_expand "v4.3.0" "uri1.0" "feature" "$UPSTREAM_DIR"
      The status should be success
      The output should include "Applied"
      The path "${UPSTREAM_DIR}/dev.txt" should be exist
      The path "${UPSTREAM_DIR}/feature.txt" should be exist
    End

    It 'excludes development dependencies with --no-dev'
      When call cmd_expand "v4.3.0" "uri1.0" "feature" "$UPSTREAM_DIR" --no-dev
      The status should be success
      The output should include "Applied"
      The path "${UPSTREAM_DIR}/dev.txt" should not be exist
      The path "${UPSTREAM_DIR}/feature.txt" should be exist
    End
  End

  Describe '--continue / --abort during conflicts'
    setup_conflict_env() {
      cd "$TEST_TMPDIR" || return 1
      cmd_init --upstream "https://github.com/mastodon/mastodon.git" "v4.3.0" >/dev/null 2>&1
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "base" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "conflict_feat" >/dev/null 2>&1 || true

      # Make conflict_feat depend on base
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      yq -i '.features.conflict_feat.dependencies = ["base"]' "$_manifest"

      # Create and tag a Git repository
      UPSTREAM_DIR="${TEST_TMPDIR}/mastodon"
      export UPSTREAM_DIR
      mkdir -p "$UPSTREAM_DIR"
      git init -b main "$UPSTREAM_DIR" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" config user.email "test@example.com"
      git -C "$UPSTREAM_DIR" config user.name "Test"
      git -C "$UPSTREAM_DIR" config tag.gpgSign false
      git -C "$UPSTREAM_DIR" config commit.gpgSign false
      git -C "$UPSTREAM_DIR" remote add origin "$UPSTREAM_DIR"
      yaml_set "$TEST_TMPDIR/manifest.yaml" ".upstream" "$UPSTREAM_DIR"
      echo "initial" > "${UPSTREAM_DIR}/README.md"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Initial commit" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" tag "v4.3.0"

      _patch_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0"

      # Base patch: add "hello" to hello.txt
      echo "hello" > "${UPSTREAM_DIR}/hello.txt"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add hello" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/base.patch"

      # Conflict patch: different content in the same file, based on the tag, to cause a conflict
      git -C "$UPSTREAM_DIR" checkout -b conflict_branch "v4.3.0" >/dev/null 2>&1
      echo "conflict content" > "${UPSTREAM_DIR}/hello.txt"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add conflict" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/conflict_feat.patch"

      # Return to the tag in preparation for expand
      git -C "$UPSTREAM_DIR" checkout -b ready_branch "v4.3.0" >/dev/null 2>&1
    }
    BeforeEach 'setup_conflict_env'

    It 'continues with --continue after resolving a conflict'
      # Run expand and conflict at conflict_feat with exit status 1
      # Use a subshell so exit status 1 does not terminate the test process
      ( cmd_expand "v4.3.0" "uri1.0" "conflict_feat" "$UPSTREAM_DIR" ) >/dev/null 2>&1 || true

      # Check that external state was created
      STATE_OPERATION="expand"
      export STATE_OPERATION
      state_in_progress "$UPSTREAM_DIR" || return 1

      # Resolve the conflict by editing the file and running git add
      echo "resolved" > "${UPSTREAM_DIR}/hello.txt"
      git -C "$UPSTREAM_DIR" add hello.txt >/dev/null 2>&1

      When call cmd_expand "$UPSTREAM_DIR" --continue
      The status should be success
      The output should include "Applied"
      The path "${UPSTREAM_DIR}/.uri_state" should not be exist
    End

    It 'aborts and restores the operation with --abort'
      # Remember the starting commit
      _start_commit=$(git -C "$UPSTREAM_DIR" rev-parse HEAD)

      # Run expand and cause a conflict
      ( cmd_expand "v4.3.0" "uri1.0" "conflict_feat" "$UPSTREAM_DIR" ) >/dev/null 2>&1 || true

      When call cmd_expand "$UPSTREAM_DIR" --abort
      The status should be success
      The output should include "aborted"
      The path "${UPSTREAM_DIR}/.uri_state" should not be exist
    End

    It 'returns HEAD to the starting commit after --abort'
      _start_commit=$(git -C "$UPSTREAM_DIR" rev-parse HEAD)

      ( cmd_expand "v4.3.0" "uri1.0" "conflict_feat" "$UPSTREAM_DIR" ) >/dev/null 2>&1 || true

      cmd_expand "$UPSTREAM_DIR" --abort >/dev/null 2>&1 || true

      When call git -C "$UPSTREAM_DIR" rev-parse HEAD
      The output should equal "$_start_commit"
    End

    It 'creates the feature branch after --continue'
      ( cmd_expand "v4.3.0" "uri1.0" "conflict_feat" "$UPSTREAM_DIR" ) >/dev/null 2>&1 || true

      echo "resolved" > "${UPSTREAM_DIR}/hello.txt"
      git -C "$UPSTREAM_DIR" add hello.txt >/dev/null 2>&1

      cmd_expand "$UPSTREAM_DIR" --continue >/dev/null 2>&1 || true

      When call git_branch_exists "$UPSTREAM_DIR" "uri/v4.3.0/uri1.0/conflict_feat"
      The status should be success
    End
  End
End
