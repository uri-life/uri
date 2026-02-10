#!/bin/sh
# apply_spec.sh - lib/commands/apply.sh 테스트

Describe 'lib/commands/apply.sh'
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
  Include "$LIB_DIR/commands/apply.sh"

  Describe 'apply_usage()'
    It '도움말을 출력한다'
      When call apply_usage
      The output should include "사용법"
      The output should include "uri apply"
    End
  End

  Describe 'cmd_apply()'
    setup_apply_env() {
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

      echo "apply-content" > "${MASTODON_DIR}/applied.txt"
      git -C "$MASTODON_DIR" add . >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Apply test" >/dev/null 2>&1

      _patch_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0"
      mkdir -p "$_patch_dir"
      git -C "$MASTODON_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/base.patch"

      git -C "$MASTODON_DIR" checkout -b temp_for_apply "v4.3.0" >/dev/null 2>&1
    }
    BeforeEach 'setup_apply_env'

    It '모든 feature를 일괄 적용한다'
      When call cmd_apply "v4.3.0" "uri1.0" "$MASTODON_DIR"
      The status should be success
      The output should include "적용 완료"
      The path "${MASTODON_DIR}/applied.txt" should be exist
    End

    It '버전 브랜치를 생성한다 (feature 브랜치가 아닌)'
      cmd_apply "v4.3.0" "uri1.0" "$MASTODON_DIR" >/dev/null 2>&1 || true
      When call git_branch_exists "$MASTODON_DIR" "uri/v4.3.0/uri1.0"
      The status should be success
    End

    It '완료 후 상태 파일이 정리된다'
      cmd_apply "v4.3.0" "uri1.0" "$MASTODON_DIR" >/dev/null 2>&1 || true
      When call state_exists "$MASTODON_DIR"
      The status should be failure
    End
  End

  Describe '충돌 시 --continue / --abort'
    setup_apply_conflict_env() {
      cd "$TEST_TMPDIR" || return 1
      cmd_init "v4.3.0" >/dev/null 2>&1
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "base" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "conflict_feat" >/dev/null 2>&1 || true

      # conflict_feat가 base에 의존하도록 설정
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      yq -i '.features.conflict_feat.dependencies = ["base"]' "$_manifest"

      # Git 리포 생성 + 태그
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

      _patch_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0"

      # base 패치: hello.txt에 "hello" 추가
      echo "hello" > "${MASTODON_DIR}/hello.txt"
      git -C "$MASTODON_DIR" add . >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Add hello" >/dev/null 2>&1
      git -C "$MASTODON_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/base.patch"

      # conflict 패치: 같은 파일에 다른 내용 (태그 기준에서 생성 → 충돌 유발)
      git -C "$MASTODON_DIR" checkout -b conflict_branch "v4.3.0" >/dev/null 2>&1
      echo "conflict content" > "${MASTODON_DIR}/hello.txt"
      git -C "$MASTODON_DIR" add . >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Add conflict" >/dev/null 2>&1
      git -C "$MASTODON_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/conflict_feat.patch"

      # 태그 위치로 복귀 (apply 시작 준비)
      git -C "$MASTODON_DIR" checkout -b ready_branch "v4.3.0" >/dev/null 2>&1
    }
    BeforeEach 'setup_apply_conflict_env'

    It '--continue로 충돌 해결 후 계속 진행한다'
      # apply 실행 → conflict_feat에서 충돌 (exit 1)
      ( cmd_apply "v4.3.0" "uri1.0" "$MASTODON_DIR" ) >/dev/null 2>&1 || true

      # 상태 파일이 생성되었는지 확인
      test -f "${MASTODON_DIR}/.uri_state" || return 1

      # 충돌 해결: 파일 수정 + git add
      echo "resolved" > "${MASTODON_DIR}/hello.txt"
      git -C "$MASTODON_DIR" add hello.txt >/dev/null 2>&1

      When call cmd_apply "$MASTODON_DIR" --continue
      The status should be success
      The output should include "적용 완료"
      The path "${MASTODON_DIR}/.uri_state" should not be exist
    End

    It '--abort로 작업을 중단하고 원복한다'
      _start_commit=$(git -C "$MASTODON_DIR" rev-parse HEAD)

      ( cmd_apply "v4.3.0" "uri1.0" "$MASTODON_DIR" ) >/dev/null 2>&1 || true

      When call cmd_apply "$MASTODON_DIR" --abort
      The status should be success
      The output should include "중단"
      The path "${MASTODON_DIR}/.uri_state" should not be exist
    End

    It '--abort 후 HEAD가 시작 커밋으로 돌아간다'
      _start_commit=$(git -C "$MASTODON_DIR" rev-parse HEAD)

      ( cmd_apply "v4.3.0" "uri1.0" "$MASTODON_DIR" ) >/dev/null 2>&1 || true

      cmd_apply "$MASTODON_DIR" --abort >/dev/null 2>&1 || true

      When call git -C "$MASTODON_DIR" rev-parse HEAD
      The output should equal "$_start_commit"
    End

    It '--continue 후 버전 브랜치가 생성된다'
      ( cmd_apply "v4.3.0" "uri1.0" "$MASTODON_DIR" ) >/dev/null 2>&1 || true

      echo "resolved" > "${MASTODON_DIR}/hello.txt"
      git -C "$MASTODON_DIR" add hello.txt >/dev/null 2>&1

      cmd_apply "$MASTODON_DIR" --continue >/dev/null 2>&1 || true

      When call git_branch_exists "$MASTODON_DIR" "uri/v4.3.0/uri1.0"
      The status should be success
    End
  End
End
