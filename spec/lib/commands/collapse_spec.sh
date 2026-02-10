#!/bin/sh
# collapse_spec.sh - lib/commands/collapse.sh 테스트

Describe 'lib/commands/collapse.sh'
  Skip if "yq가 설치되어 있지 않습니다" has_no_yq
  Skip if "git이 설치되어 있지 않습니다" has_no_git

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
    It '도움말을 출력한다'
      When call collapse_usage
      The output should include "사용법"
      The output should include "uri collapse"
    End
  End

  Describe 'cmd_collapse()'
    setup_collapse_env() {
      cd "$TEST_TMPDIR" || return 1
      cmd_init "v4.3.0" >/dev/null 2>&1
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "base" >/dev/null 2>&1 || true

      MASTODON_DIR="${TEST_TMPDIR}/mastodon"
      export MASTODON_DIR
      mkdir -p "$MASTODON_DIR"
      git init -b main "$MASTODON_DIR" >/dev/null 2>&1
      git -C "$MASTODON_DIR" config user.email "test@example.com"
      git -C "$MASTODON_DIR" config user.name "Test"
      git -C "$MASTODON_DIR" config tag.gpgSign false
      git -C "$MASTODON_DIR" config commit.gpgSign false
      echo "initial" > "${MASTODON_DIR}/README.md"
      git -C "$MASTODON_DIR" add . >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Initial commit" >/dev/null 2>&1
      git -C "$MASTODON_DIR" tag "v4.3.0"

      echo "collapse-test-content" > "${MASTODON_DIR}/feature.txt"
      git -C "$MASTODON_DIR" add . >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Add feature" >/dev/null 2>&1

      _patch_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0"
      mkdir -p "$_patch_dir"
      git -C "$MASTODON_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/base.patch"

      git -C "$MASTODON_DIR" checkout -b temp_for_collapse "v4.3.0" >/dev/null 2>&1

      # expand 실행
      cmd_expand "v4.3.0" "uri1.0" "base" "$MASTODON_DIR" >/dev/null 2>&1 || true
    }
    BeforeEach 'setup_collapse_env'

    It 'expand된 브랜치에서 패치를 추출한다'
      When call cmd_collapse "v4.3.0" "uri1.0" "base" "$MASTODON_DIR"
      The status should be success
      The output should include "collapse 완료"
    End

    It '패치 파일이 생성된다'
      cmd_collapse "v4.3.0" "uri1.0" "base" "$MASTODON_DIR" >/dev/null 2>&1 || true
      _patch="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/base.patch"
      The path "$_patch" should be exist
      The contents of file "$_patch" should include "collapse-test-content"
    End

    It 'collapse 후 feature 브랜치가 삭제된다'
      cmd_collapse "v4.3.0" "uri1.0" "base" "$MASTODON_DIR" >/dev/null 2>&1 || true
      When call git_branch_exists "$MASTODON_DIR" "uri/v4.3.0/uri1.0/base"
      The status should be failure
    End
  End
End
