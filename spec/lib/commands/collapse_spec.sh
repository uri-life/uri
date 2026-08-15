#!/bin/sh
# collapse_spec.sh - Tests for lib/commands/collapse.sh

Describe 'lib/commands/collapse.sh'
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
  Include "$LIB_DIR/commands/collapse.sh"

  Describe 'collapse_usage()'
    It 'prints help'
      When call collapse_usage
      The output should include "Usage"
      The output should include "uri collapse"
      The output should include "--recursive"
    End
  End

  Describe 'cmd_collapse()'
    run_collapse_command() {
      (cmd_collapse "$@")
    }

    setup_collapse_env() {
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

      echo "collapse-test-content" > "${UPSTREAM_DIR}/feature.txt"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add feature" >/dev/null 2>&1

      _patch_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0"
      mkdir -p "$_patch_dir"
      git -C "$UPSTREAM_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/base.patch"

      git -C "$UPSTREAM_DIR" checkout -b temp_for_collapse "v4.3.0" >/dev/null 2>&1

      # Run expand
      cmd_expand "v4.3.0" "uri1.0" "base" "$UPSTREAM_DIR" >/dev/null 2>&1 || true
    }
    BeforeEach 'setup_collapse_env'

    It 'extracts a patch from an expanded branch'
      When call cmd_collapse "v4.3.0" "uri1.0" "base" "$UPSTREAM_DIR"
      The status should be success
      The output should include "Collapse complete"
    End

    It 'creates a patch file'
      cmd_collapse "v4.3.0" "uri1.0" "base" "$UPSTREAM_DIR" >/dev/null 2>&1 || true
      _patch="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/base.patch"
      The path "$_patch" should be exist
      The contents of file "$_patch" should include "collapse-test-content"
    End

    It 'deletes the feature branch after collapse'
      cmd_collapse "v4.3.0" "uri1.0" "base" "$UPSTREAM_DIR" >/dev/null 2>&1 || true
      When call git_branch_exists "$UPSTREAM_DIR" "uri/v4.3.0/uri1.0/base"
      The status should be failure
    End

    It 'does not extract an excluded inherited feature'
      cmd_add "v4.3.0" "uri1.1" --inherits "uri1.0" >/dev/null
      _child_manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
      yaml_append_exclude "$_child_manifest" "base"
      When call run_collapse_command "v4.3.0" "uri1.1" "base" "$UPSTREAM_DIR"
      The status should be failure
      The stderr should include "Could not find feature: base"
    End
  End

  Describe 'development dependencies'
    setup_collapse_dev_env() {
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
      git_format_patch "$UPSTREAM_DIR" "v4.3.0..HEAD" "${_patch_dir}/dev_base.patch"

      git -C "$UPSTREAM_DIR" checkout -b feature_patch "v4.3.0" >/dev/null 2>&1
      echo "feature" > "${UPSTREAM_DIR}/feature.txt"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add feature" >/dev/null 2>&1
      git_format_patch "$UPSTREAM_DIR" "v4.3.0..HEAD" "${_patch_dir}/feature.patch"

      git -C "$UPSTREAM_DIR" checkout -b ready_branch "v4.3.0" >/dev/null 2>&1
      cmd_expand "v4.3.0" "uri1.0" "feature" "$UPSTREAM_DIR" >/dev/null 2>&1 || true
    }
    BeforeEach 'setup_collapse_dev_env'

    It 'includes development dependencies with collapse --recursive'
      When call cmd_collapse "v4.3.0" "uri1.0" "feature" "$UPSTREAM_DIR" --recursive
      The status should be success
      The output should include "dev_base"
      The contents of file "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/dev_base.patch" should include "dev.txt"
      The contents of file "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/feature.patch" should include "feature.txt"
    End

    It 'detects changes to development dependency features in non-recursive collapse'
      git -C "$UPSTREAM_DIR" checkout "uri/v4.3.0/uri1.0/dev_base" >/dev/null 2>&1
      echo "dev-changed" > "${UPSTREAM_DIR}/dev.txt"
      git -C "$UPSTREAM_DIR" add dev.txt >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Update dev dependency" >/dev/null 2>&1
      _dev_before=$(cksum "${_patch_dir}/dev_base.patch")
      _feature_before=$(cksum "${_patch_dir}/feature.patch")

      When call cmd_collapse "v4.3.0" "uri1.0" "feature" "$UPSTREAM_DIR"
      The status should be failure
      The output should include "temporary Git clone"
      The stderr should include "dev_base"
      The value "$(cksum "${_patch_dir}/dev_base.patch")" should eq "$_dev_before"
      The value "$(cksum "${_patch_dir}/feature.patch")" should eq "$_feature_before"
    End
  End

  Describe 'multiple dependencies'
    setup_collapse_multi_dep_env() {
      cd "$TEST_TMPDIR" || return 1
      cmd_init --upstream "https://github.com/mastodon/mastodon.git" "v4.3.0" >/dev/null 2>&1
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "dep_a" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "dep_b" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "feature" --dependencies "dep_a,dep_b" >/dev/null 2>&1 || true

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

      echo "dep-a-only" > "${UPSTREAM_DIR}/dep_a.txt"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add dep A" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/dep_a.patch"

      git -C "$UPSTREAM_DIR" checkout -b build_dep_b "v4.3.0" >/dev/null 2>&1
      echo "dep-b-only" > "${UPSTREAM_DIR}/dep_b.txt"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add dep B" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/dep_b.patch"

      git -C "$UPSTREAM_DIR" checkout -b build_feature "v4.3.0" >/dev/null 2>&1
      echo "feature-only" > "${UPSTREAM_DIR}/feature.txt"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add feature" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/feature.patch"

      git -C "$UPSTREAM_DIR" checkout -b ready_branch "v4.3.0" >/dev/null 2>&1
      cmd_expand "v4.3.0" "uri1.0" "feature" "$UPSTREAM_DIR" >/dev/null 2>&1 || true
    }
    BeforeEach 'setup_collapse_multi_dep_env'

    It 'does not mix commits from sibling dependencies during collapse'
      cmd_collapse "v4.3.0" "uri1.0" "feature" "$UPSTREAM_DIR" --recursive >/dev/null 2>&1 || true

      _dep_a_patch="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/dep_a.patch"
      _dep_b_patch="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/dep_b.patch"
      _feature_patch="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/feature.patch"

      The contents of file "$_dep_a_patch" should include "dep-a-only"
      The contents of file "$_dep_a_patch" should not include "dep-b-only"
      The contents of file "$_dep_a_patch" should not include "feature-only"

      The contents of file "$_dep_b_patch" should include "dep-b-only"
      The contents of file "$_dep_b_patch" should not include "dep-a-only"
      The contents of file "$_dep_b_patch" should not include "feature-only"

      The contents of file "$_feature_patch" should include "feature-only"
      The contents of file "$_feature_patch" should not include "dep-a-only"
      The contents of file "$_feature_patch" should not include "dep-b-only"
    End
  End

  Describe 'per-dependency rebase and transactions'
    setup_collapse_rebase_env() {
      cd "$TEST_TMPDIR" || return 1
      cmd_init --upstream "https://github.com/mastodon/mastodon.git" "v4.3.0" >/dev/null 2>&1
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "b" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "a" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "c" --dependencies "b,a" >/dev/null 2>&1 || true

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

      printf 'one\nbase-two\nthree\nfour\nfive\nsix\nseven\neight\nnine\nbase-ten\neleven\ntwelve\n' > "${UPSTREAM_DIR}/stack.txt"
      git -C "$UPSTREAM_DIR" add . >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Initial commit" >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" tag "v4.3.0"

      _patch_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0"

      git -C "$UPSTREAM_DIR" checkout -b build_a "v4.3.0" >/dev/null 2>&1
      printf 'one\na-two\nthree\nfour\nfive\nsix\nseven\neight\nnine\nbase-ten\neleven\ntwelve\n' > "${UPSTREAM_DIR}/stack.txt"
      git -C "$UPSTREAM_DIR" add stack.txt >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add A" >/dev/null 2>&1
      git_format_patch "$UPSTREAM_DIR" "v4.3.0..HEAD" "${_patch_dir}/a.patch"

      git -C "$UPSTREAM_DIR" checkout -b build_b "v4.3.0" >/dev/null 2>&1
      printf 'one\nbase-two\nthree\nfour\nfive\nsix\nseven\neight\nnine\nb-ten\neleven\ntwelve\n' > "${UPSTREAM_DIR}/stack.txt"
      git -C "$UPSTREAM_DIR" add stack.txt >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add B" >/dev/null 2>&1
      git_format_patch "$UPSTREAM_DIR" "v4.3.0..HEAD" "${_patch_dir}/b.patch"

      git -C "$UPSTREAM_DIR" checkout -b build_c "v4.3.0" >/dev/null 2>&1
      printf 'c-original\n' > "${UPSTREAM_DIR}/c.txt"
      git -C "$UPSTREAM_DIR" add c.txt >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Add C" >/dev/null 2>&1
      git_format_patch "$UPSTREAM_DIR" "v4.3.0..HEAD" "${_patch_dir}/c.patch"

      git -C "$UPSTREAM_DIR" checkout -b ready "v4.3.0" >/dev/null 2>&1
      cmd_expand "v4.3.0" "uri1.0" "c" "$UPSTREAM_DIR" >/dev/null 2>&1
    }
    BeforeEach 'setup_collapse_rebase_env'

    It 'saves only the target patch when dependent patches match in non-recursive collapse'
      _a_before=$(cksum "${_patch_dir}/a.patch")
      _b_before=$(cksum "${_patch_dir}/b.patch")
      _manifest_before=$(cksum "${_patch_dir}/manifest.yaml")
      printf 'c-updated\n' > "${UPSTREAM_DIR}/c.txt"
      git -C "$UPSTREAM_DIR" add c.txt >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Update C" >/dev/null 2>&1

      When call cmd_collapse "v4.3.0" "uri1.0" "c" "$UPSTREAM_DIR"
      The status should be success
      The output should include "Collapse complete"
      The value "$(cksum "${_patch_dir}/a.patch")" should eq "$_a_before"
      The value "$(cksum "${_patch_dir}/b.patch")" should eq "$_b_before"
      The value "$(cksum "${_patch_dir}/manifest.yaml")" should eq "$_manifest_before"
      The contents of file "${_patch_dir}/c.patch" should include "c-updated"
      The value "$(git -C "$UPSTREAM_DIR" describe --tags --exact-match HEAD)" should eq "v4.3.0"
      The value "$(git -C "$UPSTREAM_DIR" for-each-ref --format='%(refname)' refs/heads/uri/v4.3.0/uri1.0/)" should be blank
    End

    It 'rebases independent dependent features onto the tag with collapse --recursive'
      git -C "$UPSTREAM_DIR" checkout "uri/v4.3.0/uri1.0/b" >/dev/null 2>&1
      printf 'one\na-two\nthree\nfour\nfive\nsix\nseven\neight\nnine\nb-ten\neleven\ntwelve\nb-extra\n' > "${UPSTREAM_DIR}/stack.txt"
      git -C "$UPSTREAM_DIR" add stack.txt >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Update B" >/dev/null 2>&1
      _tag_blob=$(git -C "$UPSTREAM_DIR" rev-parse --short=7 "v4.3.0:stack.txt")
      _a_blob=$(git -C "$UPSTREAM_DIR" rev-parse --short=7 "uri/v4.3.0/uri1.0/a:stack.txt")

      When call cmd_collapse "v4.3.0" "uri1.0" "c" "$UPSTREAM_DIR" --recursive
      The status should be success
      The output should include "Collapse complete"
      The contents of file "${_patch_dir}/b.patch" should include "b-extra"
      The contents of file "${_patch_dir}/b.patch" should include "index ${_tag_blob}.."
      The contents of file "${_patch_dir}/b.patch" should not include "index ${_a_blob}.."
      The contents of file "${_patch_dir}/b.patch" should not include "a-two"
      The contents of file "${_patch_dir}/c.patch" should include "c-original"
      The contents of file "${_patch_dir}/c.patch" should not include "b-extra"
    End

    It 'preserves everything when non-recursive collapse detects a dependent patch change'
      git -C "$UPSTREAM_DIR" checkout "uri/v4.3.0/uri1.0/b" >/dev/null 2>&1
      printf 'one\na-two\nthree\nfour\nfive\nsix\nseven\neight\nnine\nb-ten\neleven\ntwelve\nb-changed\n' > "${UPSTREAM_DIR}/stack.txt"
      git -C "$UPSTREAM_DIR" add stack.txt >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Change B" >/dev/null 2>&1

      _a_before=$(cksum "${_patch_dir}/a.patch")
      _b_before=$(cksum "${_patch_dir}/b.patch")
      _c_before=$(cksum "${_patch_dir}/c.patch")
      _manifest_before=$(cksum "${_patch_dir}/manifest.yaml")
      _head_before=$(git -C "$UPSTREAM_DIR" rev-parse HEAD)
      _a_tip_before=$(git -C "$UPSTREAM_DIR" rev-parse "uri/v4.3.0/uri1.0/a")
      _b_tip_before=$(git -C "$UPSTREAM_DIR" rev-parse "uri/v4.3.0/uri1.0/b")
      _c_tip_before=$(git -C "$UPSTREAM_DIR" rev-parse "uri/v4.3.0/uri1.0/c")

      When call cmd_collapse "v4.3.0" "uri1.0" "c" "$UPSTREAM_DIR"
      The status should be failure
      The output should include "temporary Git clone"
      The stderr should include "b"
      The stderr should include "--recursive"
      The value "$(cksum "${_patch_dir}/a.patch")" should eq "$_a_before"
      The value "$(cksum "${_patch_dir}/b.patch")" should eq "$_b_before"
      The value "$(cksum "${_patch_dir}/c.patch")" should eq "$_c_before"
      The value "$(cksum "${_patch_dir}/manifest.yaml")" should eq "$_manifest_before"
      The value "$(git -C "$UPSTREAM_DIR" rev-parse HEAD)" should eq "$_head_before"
      The value "$(git -C "$UPSTREAM_DIR" rev-parse "uri/v4.3.0/uri1.0/a")" should eq "$_a_tip_before"
      The value "$(git -C "$UPSTREAM_DIR" rev-parse "uri/v4.3.0/uri1.0/b")" should eq "$_b_tip_before"
      The value "$(git -C "$UPSTREAM_DIR" rev-parse "uri/v4.3.0/uri1.0/c")" should eq "$_c_tip_before"
    End

    It 'preserves patches and source branches after a rebase conflict'
      git -C "$UPSTREAM_DIR" checkout "uri/v4.3.0/uri1.0/b" >/dev/null 2>&1
      printf 'one\nb-requires-a\nthree\nfour\nfive\nsix\nseven\neight\nnine\nb-ten\neleven\ntwelve\n' > "${UPSTREAM_DIR}/stack.txt"
      git -C "$UPSTREAM_DIR" add stack.txt >/dev/null 2>&1
      git -C "$UPSTREAM_DIR" commit -m "Make B require A" >/dev/null 2>&1

      _b_before=$(cksum "${_patch_dir}/b.patch")
      _head_before=$(git -C "$UPSTREAM_DIR" rev-parse HEAD)
      _b_tip_before=$(git -C "$UPSTREAM_DIR" rev-parse "uri/v4.3.0/uri1.0/b")

      When call cmd_collapse "v4.3.0" "uri1.0" "c" "$UPSTREAM_DIR" --recursive
      The status should be failure
      The output should include "temporary Git clone"
      The stderr should include "rebase"
      The value "$(cksum "${_patch_dir}/b.patch")" should eq "$_b_before"
      The value "$(git -C "$UPSTREAM_DIR" rev-parse HEAD)" should eq "$_head_before"
      The value "$(git -C "$UPSTREAM_DIR" rev-parse "uri/v4.3.0/uri1.0/b")" should eq "$_b_tip_before"
    End
  End
End
