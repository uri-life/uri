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

  Describe '개발 의존성'
    setup_apply_dev_env() {
      cd "$TEST_TMPDIR" || return 1
      cmd_init "v4.3.0" >/dev/null 2>&1
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "dev_base" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "feature" --dev-dependencies "dev_base" >/dev/null 2>&1 || true

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

      echo "dev" > "${MASTODON_DIR}/dev.txt"
      git -C "$MASTODON_DIR" add . >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Add dev dependency" >/dev/null 2>&1
      git -C "$MASTODON_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/dev_base.patch"

      git -C "$MASTODON_DIR" checkout -b feature_patch "v4.3.0" >/dev/null 2>&1
      echo "feature" > "${MASTODON_DIR}/feature.txt"
      git -C "$MASTODON_DIR" add . >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Add feature" >/dev/null 2>&1
      git -C "$MASTODON_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/feature.patch"

      git -C "$MASTODON_DIR" checkout -b ready_branch "v4.3.0" >/dev/null 2>&1
    }
    BeforeEach 'setup_apply_dev_env'

    It 'apply는 개발 의존성 전용 feature를 적용하지 않는다'
      When call cmd_apply "v4.3.0" "uri1.0" "$MASTODON_DIR"
      The status should be success
      The output should include "적용 완료"
      The path "${MASTODON_DIR}/dev.txt" should not be exist
      The path "${MASTODON_DIR}/feature.txt" should be exist
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

      # 외부 상태가 생성되었는지 확인
      STATE_OPERATION="apply"
      export STATE_OPERATION
      state_in_progress "$MASTODON_DIR" || return 1

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

  Describe 'apply resolution patches'
    create_apply_patch_from_tag() {
      _branch="$1"
      _file="$2"
      _content="$3"
      _subject="$4"
      _output="$5"

      git -C "$MASTODON_DIR" checkout -B "$_branch" "v4.3.0" >/dev/null 2>&1
      printf '%s\n' "$_content" > "${MASTODON_DIR}/${_file}"
      git -C "$MASTODON_DIR" add . >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "$_subject" >/dev/null 2>&1
      git -C "$MASTODON_DIR" format-patch --stdout "v4.3.0..HEAD" > "$_output"
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
      cmd_init "v4.3.0" >/dev/null 2>&1
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "a" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "b" --dependencies "a" >/dev/null 2>&1 || true

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
      git -C "$MASTODON_DIR" checkout -B ready_branch "v4.3.0" >/dev/null 2>&1
    }

    It 'ANTE, main, POST 순서로 적용한다'
      setup_apply_order_env
      cmd_apply "v4.3.0" "uri1.0" "$MASTODON_DIR" >/dev/null 2>&1
      When call apply_subjects "$MASTODON_DIR"
      The output should eq "a ante|a main|a post|b ante|b main|b post|"
    End

    setup_apply_pair_env() {
      setup_apply_resolution_env

      git -C "$MASTODON_DIR" checkout -B a_patch "v4.3.0" >/dev/null 2>&1
      printf 'a\n' > "${MASTODON_DIR}/conflict.txt"
      git -C "$MASTODON_DIR" add conflict.txt >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Add a" >/dev/null 2>&1
      git -C "$MASTODON_DIR" format-patch --stdout "v4.3.0..HEAD" > "${PATCH_DIR}/a.patch"

      git -C "$MASTODON_DIR" checkout -B b_patch "v4.3.0" >/dev/null 2>&1
      printf 'b\n' > "${MASTODON_DIR}/conflict.txt"
      git -C "$MASTODON_DIR" add conflict.txt >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Add b" >/dev/null 2>&1
      git -C "$MASTODON_DIR" format-patch --stdout "v4.3.0..HEAD" > "${PATCH_DIR}/b.patch"

      create_apply_patch_from_tag "b_post_patch" "post.txt" "post" "Add post" "${PATCH_DIR}/b~POST.patch"

      git -C "$MASTODON_DIR" checkout -B pair_source "v4.3.0" >/dev/null 2>&1
      git_am "$MASTODON_DIR" "${PATCH_DIR}/a.patch" >/dev/null 2>&1
      git_am "$MASTODON_DIR" "${PATCH_DIR}/b.patch" >/dev/null 2>&1 || true
      cp "${MASTODON_DIR}/conflict.txt" "${TEST_TMPDIR}/conflict.before"
      printf 'a\nb\n' > "${TEST_TMPDIR}/conflict.after"
      ( cd "$TEST_TMPDIR" && git diff --no-index -- conflict.before conflict.after ) | \
        sed 's|--- a/conflict.before|--- a/conflict.txt|; s|+++ b/conflict.after|+++ b/conflict.txt|' > "${PATCH_DIR}/b~a.patch"
      git -C "$MASTODON_DIR" am --abort >/dev/null 2>&1 || true
      git -C "$MASTODON_DIR" checkout -B ready_branch "v4.3.0" >/dev/null 2>&1
    }

    It 'main 패치 충돌 시 pair 패치를 적용하고 POST로 이어간다'
      setup_apply_pair_env
      When call cmd_apply "v4.3.0" "uri1.0" "$MASTODON_DIR"
      The status should be success
      The output should include "충돌 해소 패치 적용 완료"
      The contents of file "${MASTODON_DIR}/conflict.txt" should include "a"
      The contents of file "${MASTODON_DIR}/conflict.txt" should include "b"
      The path "${MASTODON_DIR}/post.txt" should be exist
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
      git -C "$MASTODON_DIR" checkout -B ready_branch "v4.3.0" >/dev/null 2>&1
    }

    It 'main 패치가 충돌하지 않으면 pair 패치를 적용하지 않는다'
      setup_apply_pair_skip_env
      When call cmd_apply "v4.3.0" "uri1.0" "$MASTODON_DIR"
      The status should be success
      The output should include "적용 완료"
      The path "${MASTODON_DIR}/pair.txt" should not be exist
    End

    It 'pair 패치 적용 실패 시 기존 수동 복구 상태를 유지한다'
      setup_apply_pair_env
      echo "not a patch" > "${PATCH_DIR}/b~a.patch"
      ( cmd_apply "v4.3.0" "uri1.0" "$MASTODON_DIR" ) >/dev/null 2>&1 || true
      When call apply_state_and_am_in_progress "$MASTODON_DIR"
      The status should be success
    End
  End
End
