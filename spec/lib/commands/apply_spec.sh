#!/bin/sh
# apply_spec.sh - Tests for lib/commands/apply.sh

Describe 'lib/commands/apply.sh'
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
  Include "$LIB_DIR/commands/apply.sh"

  Describe 'apply_usage()'
    It 'prints help'
      When call apply_usage
      The output should include "Usage"
      The output should include "uri apply"
    End
  End

  Describe 'cmd_apply()'
    setup_apply_env() {
      cd "$TEST_TMPDIR" || return 1
      cmd_init --upstream "https://github.com/mastodon/mastodon.git" "v4.3.0" >/dev/null 2>&1
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "base" >/dev/null 2>&1 || true

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

      echo "apply-content" > "${UPSTREAM_DIR}/applied.txt"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Apply test" >/dev/null 2>&1

      _patch_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0"
      mkdir -p "$_patch_dir"
      git -C "$UPSTREAM_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/base.patch"

      git -C "$UPSTREAM_DIR" checkout -b temp_for_apply "v4.3.0" >/dev/null 2>&1
    }
    BeforeEach 'setup_apply_env'

    It 'applies all features'
      When call cmd_apply "v4.3.0" "uri1.0" "$UPSTREAM_DIR"
      The status should be success
      The output should include "Applied"
      The path "${UPSTREAM_DIR}/applied.txt" should be exist
    End

    It 'creates a version branch rather than feature branches'
      cmd_apply "v4.3.0" "uri1.0" "$UPSTREAM_DIR" >/dev/null 2>&1 || true
      When call git_branch_exists "$UPSTREAM_DIR" "uri/v4.3.0/uri1.0"
      The status should be success
    End

    It 'clears the state file after completion'
      cmd_apply "v4.3.0" "uri1.0" "$UPSTREAM_DIR" >/dev/null 2>&1 || true
      When call state_exists "$UPSTREAM_DIR"
      The status should be failure
    End

    It 'removes an excluded inherited feature from the apply set'
      cmd_add "v4.3.0" "uri1.1" --inherits "uri1.0" >/dev/null
      _child_manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
      yaml_append_exclude "$_child_manifest" "base"
      When call cmd_apply "v4.3.0" "uri1.1" "$UPSTREAM_DIR"
      The status should be success
      The stderr should include "No features to apply."
      The path "${UPSTREAM_DIR}/applied.txt" should not be exist
    End
  End

  Describe 'development dependencies'
    setup_apply_dev_env() {
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
    BeforeEach 'setup_apply_dev_env'

    It 'does not apply development-only features'
      When call cmd_apply "v4.3.0" "uri1.0" "$UPSTREAM_DIR"
      The status should be success
      The output should include "Applied"
      The path "${UPSTREAM_DIR}/dev.txt" should not be exist
      The path "${UPSTREAM_DIR}/feature.txt" should be exist
    End
  End

  Describe '--continue / --abort during conflicts'
    setup_apply_conflict_env() {
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

      # Return to the tag in preparation for apply
      git -C "$UPSTREAM_DIR" checkout -b ready_branch "v4.3.0" >/dev/null 2>&1
    }
    BeforeEach 'setup_apply_conflict_env'

    It 'continues with --continue after resolving a conflict'
      # Run apply and conflict at conflict_feat with exit status 1
      ( cmd_apply "v4.3.0" "uri1.0" "$UPSTREAM_DIR" ) >/dev/null 2>&1 || true

      # Check that external state was created
      STATE_OPERATION="apply"
      export STATE_OPERATION
      state_in_progress "$UPSTREAM_DIR" || return 1

      # Resolve the conflict by editing the file and running git add
      echo "resolved" > "${UPSTREAM_DIR}/hello.txt"
      git -C "$UPSTREAM_DIR" add hello.txt >/dev/null 2>&1

      When call cmd_apply "$UPSTREAM_DIR" --continue
      The status should be success
      The output should include "Applied"
      The path "${UPSTREAM_DIR}/.uri_state" should not be exist
    End

    It 'aborts and restores the operation with --abort'
      _start_commit=$(git -C "$UPSTREAM_DIR" rev-parse HEAD)

      ( cmd_apply "v4.3.0" "uri1.0" "$UPSTREAM_DIR" ) >/dev/null 2>&1 || true

      When call cmd_apply "$UPSTREAM_DIR" --abort
      The status should be success
      The output should include "aborted"
      The path "${UPSTREAM_DIR}/.uri_state" should not be exist
    End

    It 'returns HEAD to the starting commit after --abort'
      _start_commit=$(git -C "$UPSTREAM_DIR" rev-parse HEAD)

      ( cmd_apply "v4.3.0" "uri1.0" "$UPSTREAM_DIR" ) >/dev/null 2>&1 || true

      cmd_apply "$UPSTREAM_DIR" --abort >/dev/null 2>&1 || true

      When call git -C "$UPSTREAM_DIR" rev-parse HEAD
      The output should equal "$_start_commit"
    End

    It 'creates the version branch after --continue'
      ( cmd_apply "v4.3.0" "uri1.0" "$UPSTREAM_DIR" ) >/dev/null 2>&1 || true

      echo "resolved" > "${UPSTREAM_DIR}/hello.txt"
      git -C "$UPSTREAM_DIR" add hello.txt >/dev/null 2>&1

      cmd_apply "$UPSTREAM_DIR" --continue >/dev/null 2>&1 || true

      When call git_branch_exists "$UPSTREAM_DIR" "uri/v4.3.0/uri1.0"
      The status should be success
    End
  End

  Describe 'apply resolution patches'
    create_apply_patch_from_tag() {
      _branch="$1"
      _file="$2"
      _content="$3"
      _subject="$4"
      _output="$5"

      git -C "$UPSTREAM_DIR" checkout -B "$_branch" "v4.3.0" >/dev/null 2>&1
      printf '%s\n' "$_content" > "${UPSTREAM_DIR}/${_file}"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "$_subject" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" format-patch --stdout "v4.3.0..HEAD" > "$_output"
    }

    apply_subjects() {
      _repo="$1"
      git -C "$_repo" log --reverse --format=%s "v4.3.0..HEAD" | tr '\n' '|'
    }

    apply_state_and_am_in_progress() {
      _repo="$1"
      STATE_OPERATION="apply"
      export STATE_OPERATION
      state_in_progress "$_repo" && git_am_in_progress "$_repo"
    }

    setup_apply_resolution_env() {
      cd "$TEST_TMPDIR" || return 1
      cmd_init --upstream "https://github.com/mastodon/mastodon.git" "v4.3.0" >/dev/null 2>&1
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "a" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "b" --dependencies "a" >/dev/null 2>&1 || true

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

      PATCH_DIR="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0"
      export PATCH_DIR
    }

    setup_apply_order_env() {
      setup_apply_resolution_env
      create_apply_patch_from_tag "a_ante_patch" "a_ante.txt" "a ante" "a ante" "${PATCH_DIR}/a~ANTE.patch"
      create_apply_patch_from_tag "a_patch" "a.txt" "a" "a main" "${PATCH_DIR}/a.patch"
      create_apply_patch_from_tag "a_post_patch" "a_post.txt" "a post" "a post" "${PATCH_DIR}/a~POST.patch"
      create_apply_patch_from_tag "b_ante_patch" "b_ante.txt" "b ante" "b ante" "${PATCH_DIR}/b~ANTE.patch"
      create_apply_patch_from_tag "b_patch" "b.txt" "b" "b main" "${PATCH_DIR}/b.patch"
      create_apply_patch_from_tag "b_post_patch" "b_post.txt" "b post" "b post" "${PATCH_DIR}/b~POST.patch"
      git -C "$UPSTREAM_DIR" checkout -B ready_branch "v4.3.0" >/dev/null 2>&1
    }

    It 'applies ANTE, main, and POST in order'
      setup_apply_order_env
      cmd_apply "v4.3.0" "uri1.0" "$UPSTREAM_DIR" >/dev/null 2>&1
      When call apply_subjects "$UPSTREAM_DIR"
      The output should eq "a ante|a main|a post|b ante|b main|b post|"
    End

    setup_apply_pair_env() {
      setup_apply_resolution_env

      git -C "$UPSTREAM_DIR" checkout -B a_patch "v4.3.0" >/dev/null 2>&1
      printf 'a\n' > "${UPSTREAM_DIR}/conflict.txt"
      git -C "$UPSTREAM_DIR" add conflict.txt >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add a" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" format-patch --stdout "v4.3.0..HEAD" > "${PATCH_DIR}/a.patch"

      git -C "$UPSTREAM_DIR" checkout -B b_patch "v4.3.0" >/dev/null 2>&1
      printf 'b\n' > "${UPSTREAM_DIR}/conflict.txt"
      git -C "$UPSTREAM_DIR" add conflict.txt >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add b" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" format-patch --stdout "v4.3.0..HEAD" > "${PATCH_DIR}/b.patch"

      create_apply_patch_from_tag "b_post_patch" "post.txt" "post" "Add post" "${PATCH_DIR}/b~POST.patch"

      git -C "$UPSTREAM_DIR" checkout -B pair_source "v4.3.0" >/dev/null 2>&1
      git_am "$UPSTREAM_DIR" "${PATCH_DIR}/a.patch" >/dev/null 2>&1
      git_am "$UPSTREAM_DIR" "${PATCH_DIR}/b.patch" >/dev/null 2>&1 || true
      cp "${UPSTREAM_DIR}/conflict.txt" "${TEST_TMPDIR}/conflict.before"
      printf 'a\nb\n' > "${TEST_TMPDIR}/conflict.after"
      ( cd "$TEST_TMPDIR" && git diff --no-index -- conflict.before conflict.after ) | \
        sed 's|--- a/conflict.before|--- a/conflict.txt|; s|+++ b/conflict.after|+++ b/conflict.txt|' > "${PATCH_DIR}/b~a.patch"
      git -C "$UPSTREAM_DIR" am --abort >/dev/null 2>&1 || true
      git -C "$UPSTREAM_DIR" checkout -B ready_branch "v4.3.0" >/dev/null 2>&1
    }

    It 'applies a pair patch after a main patch conflict and continues to POST'
      setup_apply_pair_env
      When call cmd_apply "v4.3.0" "uri1.0" "$UPSTREAM_DIR"
      The status should be success
      The output should include "Applied conflict-resolution patch"
      The contents of file "${UPSTREAM_DIR}/conflict.txt" should include "a"
      The contents of file "${UPSTREAM_DIR}/conflict.txt" should include "b"
      The path "${UPSTREAM_DIR}/post.txt" should be exist
    End

    setup_apply_pair_skip_env() {
      setup_apply_resolution_env
      create_apply_patch_from_tag "a_patch" "a.txt" "a" "Add a" "${PATCH_DIR}/a.patch"
      create_apply_patch_from_tag "b_patch" "b.txt" "b" "Add b" "${PATCH_DIR}/b.patch"
      cat > "${PATCH_DIR}/b~a.patch" <<'EOF'
diff --git a/pair.txt b/pair.txt
new file mode 100644
index 0000000..9daeafb
--- /dev/null
+++ b/pair.txt
@@ -0,0 +1 @@
+pair
EOF
      git -C "$UPSTREAM_DIR" checkout -B ready_branch "v4.3.0" >/dev/null 2>&1
    }

    It 'does not apply a pair patch when the main patch does not conflict'
      setup_apply_pair_skip_env
      When call cmd_apply "v4.3.0" "uri1.0" "$UPSTREAM_DIR"
      The status should be success
      The output should include "Applied"
      The path "${UPSTREAM_DIR}/pair.txt" should not be exist
    End

    It 'preserves the existing manual recovery state when pair patch application fails'
      setup_apply_pair_env
      echo "not a patch" > "${PATCH_DIR}/b~a.patch"
      ( cmd_apply "v4.3.0" "uri1.0" "$UPSTREAM_DIR" ) >/dev/null 2>&1 || true
      When call apply_state_and_am_in_progress "$UPSTREAM_DIR"
      The status should be success
    End
  End
End
