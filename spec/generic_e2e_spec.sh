#!/bin/sh
# generic_e2e_spec.sh - General-purpose Git patchset end-to-end tests

Describe 'general-purpose Git patchset E2E'
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
  Include "$LIB_DIR/commands/list.sh"
  Include "$LIB_DIR/commands/expand.sh"
  Include "$LIB_DIR/commands/collapse.sh"
  Include "$LIB_DIR/commands/apply.sh"
  Include "$LIB_DIR/commands/graph.sh"

  setup_generic_patchset() {
    STATE_DIR="$TEST_TMPDIR/state"
    export STATE_DIR

    GENERIC_SOURCE="$TEST_TMPDIR/project-source"
    GENERIC_ROOT="$TEST_TMPDIR/patchset"
    export GENERIC_SOURCE GENERIC_ROOT

    create_test_git_repo "$GENERIC_SOURCE"
    git -C "$GENERIC_SOURCE" tag "v1.2.3"
    echo "generic feature" > "$GENERIC_SOURCE/feature.txt"
    git -C "$GENERIC_SOURCE" add feature.txt
    git -C "$GENERIC_SOURCE" commit -m "Add generic feature" >/dev/null

    mkdir -p "$GENERIC_ROOT"
    cd "$GENERIC_ROOT" || return 1
    cmd_init --upstream "$GENERIC_SOURCE" --branch-prefix custom \
      --committer-name "Patch Bot" --committer-email "patch@example.com" \
      "v1.2.3" >/dev/null
    URI_ROOT="$GENERIC_ROOT"
    export URI_ROOT
    cmd_add "v1.2.3" "patch1.0" >/dev/null
    cmd_add "v1.2.3" "patch1.0" "feature-a" >/dev/null
    git -C "$GENERIC_SOURCE" format-patch --stdout "v1.2.3..HEAD" > \
      "$GENERIC_ROOT/versions/v1.2.3/patches/patch1.0/feature-a.patch"

    cmd_add "v1.2.3" "patch1.1" --inherits "patch1.0" >/dev/null
    cmd_add "v1.2.3" "patch1.1" "feature-b" --dependencies "feature-a" >/dev/null
  }
  BeforeEach 'setup_generic_patchset'

  auto_apply_flow() {
    _e2e_output=$(cmd_apply "v1.2.3" "patch1.0" 2>&1) || {
      printf '%s\n' "$_e2e_output"
      return 1
    }
    _e2e_destination=$(printf '%s\n' "$_e2e_output" | sed -n 's/^info: Automatically created destination: //p' | tail -n 1)
    [ -d "$_e2e_destination/.git" ] || return 1
    [ "$(git -C "$_e2e_destination" rev-parse --is-shallow-repository)" = "false" ] || return 1
    git_branch_exists "$_e2e_destination" "custom/v1.2.3/patch1.0" || return 1
    [ "$(git -C "$_e2e_destination" log -1 --format='%cn <%ce>')" = "Patch Bot <patch@example.com>" ] || return 1
    [ -f "$_e2e_destination/feature.txt" ] || return 1
    printf '%s\n' "$_e2e_output"
    echo "verified destination: $_e2e_destination"
  }

  It 'apply without a destination preserves a full clone and uses a custom prefix and explicit committer'
    When call auto_apply_flow
    The status should be success
    The output should include 'Preserved automatic clone'
    The output should include 'custom/v1.2.3/patch1.0'
    The output should include 'verified destination:'
  End

  auto_expand_collapse_flow() {
    _e2e_output=$(cmd_expand "v1.2.3" "patch1.0" "feature-a" 2>&1) || {
      printf '%s\n' "$_e2e_output"
      return 1
    }
    _e2e_destination=$(printf '%s\n' "$_e2e_output" | sed -n 's/^info: Automatically created destination: //p' | tail -n 1)
    [ -d "$_e2e_destination/.git" ] || return 1
    git_branch_exists "$_e2e_destination" "custom/v1.2.3/patch1.0/feature-a" || return 1
    cmd_collapse "v1.2.3" "patch1.0" "feature-a" "$_e2e_destination" >/dev/null || return 1
    ! git_branch_exists "$_e2e_destination" "custom/v1.2.3/patch1.0/feature-a" || return 1
    [ -s "$GENERIC_ROOT/versions/v1.2.3/patches/patch1.0/feature-a.patch" ] || return 1
    printf '%s\n' "$_e2e_output"
    echo "collapsed destination: $_e2e_destination"
  }

  It 'expand without a destination preserves the clone and collapse extracts it again'
    When call auto_expand_collapse_flow
    The status should be success
    The output should include 'Preserved automatic clone'
    The output should include 'collapsed destination:'
  End

  repository_committer_flow() {
    yq eval -i '.committer = {"mode": "repository"}' "$GENERIC_ROOT/manifest.yaml"
    _e2e_destination="$TEST_TMPDIR/repository-target"
    git clone --quiet "$GENERIC_SOURCE" "$_e2e_destination" || return 1
    git -C "$_e2e_destination" config user.name "Repository User"
    git -C "$_e2e_destination" config user.email "repository@example.com"
    cmd_apply "v1.2.3" "patch1.0" "$_e2e_destination" >/dev/null || return 1
    git -C "$_e2e_destination" log -1 --format='%cn <%ce>'
  }

  It 'repository committer mode uses the target repository identity'
    When call repository_committer_flow
    The status should be success
    The output should eq 'Repository User <repository@example.com>'
  End

  legacy_manifest_flow() {
    URI_LEGACY_UPSTREAM="$GENERIC_SOURCE" yq -n '{"upstream": strenv(URI_LEGACY_UPSTREAM)}' > "$GENERIC_ROOT/manifest.yaml"
    _e2e_destination="$TEST_TMPDIR/legacy-target"
    git clone --quiet "$GENERIC_SOURCE" "$_e2e_destination" || return 1
    cmd_apply "v1.2.3" "patch1.0" "$_e2e_destination" >/dev/null || return 1
    git_branch_exists "$_e2e_destination" "uri/v1.2.3/patch1.0" || return 1
    git -C "$_e2e_destination" log -1 --format='%cn <%ce>'
  }

  It 'a legacy manifest retains the default uri prefix and URI committer'
    When call legacy_manifest_flow
    The status should be success
    The output should eq 'URI <uri@uri.life>'
  End

  missing_repository_identity_is_unchanged() {
    yq eval -i '.committer = {"mode": "repository"}' "$GENERIC_ROOT/manifest.yaml"
    _e2e_destination="$TEST_TMPDIR/no-identity"
    git clone --quiet "$GENERIC_SOURCE" "$_e2e_destination" || return 1
    git -C "$_e2e_destination" config --unset-all user.name >/dev/null 2>&1 || true
    git -C "$_e2e_destination" config --unset-all user.email >/dev/null 2>&1 || true
    _e2e_head=$(git -C "$_e2e_destination" rev-parse HEAD)
    (
      GIT_CONFIG_GLOBAL=/dev/null
      GIT_CONFIG_SYSTEM=/dev/null
      export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
      cmd_apply "v1.2.3" "patch1.0" "$_e2e_destination" >/dev/null 2>&1
    ) && return 1
    [ "$(git -C "$_e2e_destination" rev-parse HEAD)" = "$_e2e_head" ] || return 1
    [ "$(git -C "$_e2e_destination" for-each-ref --format='%(refname)' refs/heads)" = "refs/heads/main" ] || return 1
    ! state_exists "$_e2e_destination"
  }

  It 'fails before making changes when repository identity is missing'
    When call missing_repository_identity_is_unchanged
    The status should be success
  End

  It 'resolves an inherited non-uri patchset in list'
    When call cmd_list "v1.2.3" "patch1.1"
    The output should include 'feature-a'
    The output should include 'feature-b'
    The status should be success
  End

  It 'prints the graph of an inherited non-uri patchset'
    When call cmd_graph "v1.2.3" "patch1.1"
    The status should be success
    The output should include 'feature-a'
    The output should include 'feature-b'
  End

  origin_mismatch_is_unchanged() {
    _e2e_destination="$TEST_TMPDIR/wrong-origin"
    git clone --quiet "$GENERIC_SOURCE" "$_e2e_destination" || return 1
    git -C "$_e2e_destination" remote set-url origin "https://example.invalid/other.git"
    _e2e_head=$(git -C "$_e2e_destination" rev-parse HEAD)
    _e2e_refs=$(git -C "$_e2e_destination" for-each-ref --format='%(refname):%(objectname)' refs/heads)
    _e2e_patch=$(shasum -a 256 "$GENERIC_ROOT/versions/v1.2.3/patches/patch1.0/feature-a.patch" | awk '{print $1}')

    if (cmd_apply "v1.2.3" "patch1.0" "$_e2e_destination" >/dev/null 2>&1); then
      return 1
    fi

    [ "$(git -C "$_e2e_destination" rev-parse HEAD)" = "$_e2e_head" ] || return 1
    [ "$(git -C "$_e2e_destination" for-each-ref --format='%(refname):%(objectname)' refs/heads)" = "$_e2e_refs" ] || return 1
    [ "$(shasum -a 256 "$GENERIC_ROOT/versions/v1.2.3/patches/patch1.0/feature-a.patch" | awk '{print $1}')" = "$_e2e_patch" ] || return 1
    ! state_exists "$_e2e_destination"
  }

  It 'an invalid origin leaves HEAD, branches, patches, and state unchanged'
    When call origin_mismatch_is_unchanged
    The status should be success
  End

  invalid_identifier_is_unchanged() {
    _e2e_destination="$TEST_TMPDIR/invalid-identifier"
    git clone --quiet "$GENERIC_SOURCE" "$_e2e_destination" || return 1
    _e2e_head=$(git -C "$_e2e_destination" rev-parse HEAD)
    if (cmd_apply "bad/version" "patch1.0" "$_e2e_destination" >/dev/null 2>&1); then
      return 1
    fi
    [ "$(git -C "$_e2e_destination" rev-parse HEAD)" = "$_e2e_head" ] || return 1
    [ "$(git -C "$_e2e_destination" for-each-ref --format='%(refname)' refs/heads)" = "refs/heads/main" ] || return 1
    ! state_exists "$_e2e_destination"
  }

  It 'an invalid identifier leaves HEAD, branches, and state unchanged'
    When call invalid_identifier_is_unchanged
    The status should be success
  End
End
