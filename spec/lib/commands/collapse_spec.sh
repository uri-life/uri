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
      The output should include "--recursive"
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

  Describe '개발 의존성'
    setup_collapse_dev_env() {
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
      git_format_patch "$MASTODON_DIR" "v4.3.0..HEAD" "${_patch_dir}/dev_base.patch"

      git -C "$MASTODON_DIR" checkout -b feature_patch "v4.3.0" >/dev/null 2>&1
      echo "feature" > "${MASTODON_DIR}/feature.txt"
      git -C "$MASTODON_DIR" add . >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Add feature" >/dev/null 2>&1
      git_format_patch "$MASTODON_DIR" "v4.3.0..HEAD" "${_patch_dir}/feature.patch"

      git -C "$MASTODON_DIR" checkout -b ready_branch "v4.3.0" >/dev/null 2>&1
      cmd_expand "v4.3.0" "uri1.0" "feature" "$MASTODON_DIR" >/dev/null 2>&1 || true
    }
    BeforeEach 'setup_collapse_dev_env'

    It 'collapse --recursive는 개발 의존성을 포함한다'
      When call cmd_collapse "v4.3.0" "uri1.0" "feature" "$MASTODON_DIR" --recursive
      The status should be success
      The output should include "dev_base"
      The contents of file "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/dev_base.patch" should include "dev.txt"
      The contents of file "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/feature.patch" should include "feature.txt"
    End

    It '비재귀 collapse는 개발 의존 feature 변경도 검출한다'
      git -C "$MASTODON_DIR" checkout "uri/v4.3.0/uri1.0/dev_base" >/dev/null 2>&1
      echo "dev-changed" > "${MASTODON_DIR}/dev.txt"
      git -C "$MASTODON_DIR" add dev.txt >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Update dev dependency" >/dev/null 2>&1
      _dev_before=$(cksum "${_patch_dir}/dev_base.patch")
      _feature_before=$(cksum "${_patch_dir}/feature.patch")

      When call cmd_collapse "v4.3.0" "uri1.0" "feature" "$MASTODON_DIR"
      The status should be failure
      The output should include "임시 Git clone"
      The stderr should include "dev_base"
      The value "$(cksum "${_patch_dir}/dev_base.patch")" should eq "$_dev_before"
      The value "$(cksum "${_patch_dir}/feature.patch")" should eq "$_feature_before"
    End
  End

  Describe '다중 의존성'
    setup_collapse_multi_dep_env() {
      cd "$TEST_TMPDIR" || return 1
      cmd_init "v4.3.0" >/dev/null 2>&1
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "dep_a" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "dep_b" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "feature" --dependencies "dep_a,dep_b" >/dev/null 2>&1 || true

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

      echo "dep-a-only" > "${MASTODON_DIR}/dep_a.txt"
      git -C "$MASTODON_DIR" add . >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Add dep A" >/dev/null 2>&1
      git -C "$MASTODON_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/dep_a.patch"

      git -C "$MASTODON_DIR" checkout -b build_dep_b "v4.3.0" >/dev/null 2>&1
      echo "dep-b-only" > "${MASTODON_DIR}/dep_b.txt"
      git -C "$MASTODON_DIR" add . >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Add dep B" >/dev/null 2>&1
      git -C "$MASTODON_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/dep_b.patch"

      git -C "$MASTODON_DIR" checkout -b build_feature "v4.3.0" >/dev/null 2>&1
      echo "feature-only" > "${MASTODON_DIR}/feature.txt"
      git -C "$MASTODON_DIR" add . >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Add feature" >/dev/null 2>&1
      git -C "$MASTODON_DIR" format-patch --stdout "v4.3.0..HEAD" > "${_patch_dir}/feature.patch"

      git -C "$MASTODON_DIR" checkout -b ready_branch "v4.3.0" >/dev/null 2>&1
      cmd_expand "v4.3.0" "uri1.0" "feature" "$MASTODON_DIR" >/dev/null 2>&1 || true
    }
    BeforeEach 'setup_collapse_multi_dep_env'

    It 'collapse는 sibling 의존성 커밋을 서로 섞지 않는다'
      cmd_collapse "v4.3.0" "uri1.0" "feature" "$MASTODON_DIR" --recursive >/dev/null 2>&1 || true

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

  Describe '의존성별 rebase와 트랜잭션'
    setup_collapse_rebase_env() {
      cd "$TEST_TMPDIR" || return 1
      cmd_init "v4.3.0" >/dev/null 2>&1
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "b" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "a" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "c" --dependencies "b,a" >/dev/null 2>&1 || true

      MASTODON_DIR="${TEST_TMPDIR}/mastodon"
      export MASTODON_DIR
      mkdir -p "$MASTODON_DIR"
      git init -b main "$MASTODON_DIR" >/dev/null 2>&1
      git -C "$MASTODON_DIR" config user.email "test@example.com"
      git -C "$MASTODON_DIR" config user.name "Test"
      git -C "$MASTODON_DIR" config tag.gpgSign false
      git -C "$MASTODON_DIR" config commit.gpgSign false

      printf 'one\nbase-two\nthree\nfour\nfive\nsix\nseven\neight\nnine\nbase-ten\neleven\ntwelve\n' > "${MASTODON_DIR}/stack.txt"
      git -C "$MASTODON_DIR" add . >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Initial commit" >/dev/null 2>&1
      git -C "$MASTODON_DIR" tag "v4.3.0"

      _patch_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0"

      git -C "$MASTODON_DIR" checkout -b build_a "v4.3.0" >/dev/null 2>&1
      printf 'one\na-two\nthree\nfour\nfive\nsix\nseven\neight\nnine\nbase-ten\neleven\ntwelve\n' > "${MASTODON_DIR}/stack.txt"
      git -C "$MASTODON_DIR" add stack.txt >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Add A" >/dev/null 2>&1
      git_format_patch "$MASTODON_DIR" "v4.3.0..HEAD" "${_patch_dir}/a.patch"

      git -C "$MASTODON_DIR" checkout -b build_b "v4.3.0" >/dev/null 2>&1
      printf 'one\nbase-two\nthree\nfour\nfive\nsix\nseven\neight\nnine\nb-ten\neleven\ntwelve\n' > "${MASTODON_DIR}/stack.txt"
      git -C "$MASTODON_DIR" add stack.txt >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Add B" >/dev/null 2>&1
      git_format_patch "$MASTODON_DIR" "v4.3.0..HEAD" "${_patch_dir}/b.patch"

      git -C "$MASTODON_DIR" checkout -b build_c "v4.3.0" >/dev/null 2>&1
      printf 'c-original\n' > "${MASTODON_DIR}/c.txt"
      git -C "$MASTODON_DIR" add c.txt >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Add C" >/dev/null 2>&1
      git_format_patch "$MASTODON_DIR" "v4.3.0..HEAD" "${_patch_dir}/c.patch"

      git -C "$MASTODON_DIR" checkout -b ready "v4.3.0" >/dev/null 2>&1
      cmd_expand "v4.3.0" "uri1.0" "c" "$MASTODON_DIR" >/dev/null 2>&1
    }
    BeforeEach 'setup_collapse_rebase_env'

    It '비재귀 collapse는 의존 패치가 같으면 대상 패치만 저장한다'
      _a_before=$(cksum "${_patch_dir}/a.patch")
      _b_before=$(cksum "${_patch_dir}/b.patch")
      _manifest_before=$(cksum "${_patch_dir}/manifest.yaml")
      printf 'c-updated\n' > "${MASTODON_DIR}/c.txt"
      git -C "$MASTODON_DIR" add c.txt >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Update C" >/dev/null 2>&1

      When call cmd_collapse "v4.3.0" "uri1.0" "c" "$MASTODON_DIR"
      The status should be success
      The output should include "collapse 완료"
      The value "$(cksum "${_patch_dir}/a.patch")" should eq "$_a_before"
      The value "$(cksum "${_patch_dir}/b.patch")" should eq "$_b_before"
      The value "$(cksum "${_patch_dir}/manifest.yaml")" should eq "$_manifest_before"
      The contents of file "${_patch_dir}/c.patch" should include "c-updated"
      The value "$(git -C "$MASTODON_DIR" describe --tags --exact-match HEAD)" should eq "v4.3.0"
      The value "$(git -C "$MASTODON_DIR" for-each-ref --format='%(refname)' refs/heads/uri/v4.3.0/uri1.0/)" should be blank
    End

    It 'collapse --recursive는 독립 의존 feature를 태그 위로 rebase한다'
      git -C "$MASTODON_DIR" checkout "uri/v4.3.0/uri1.0/b" >/dev/null 2>&1
      printf 'one\na-two\nthree\nfour\nfive\nsix\nseven\neight\nnine\nb-ten\neleven\ntwelve\nb-extra\n' > "${MASTODON_DIR}/stack.txt"
      git -C "$MASTODON_DIR" add stack.txt >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Update B" >/dev/null 2>&1
      _tag_blob=$(git -C "$MASTODON_DIR" rev-parse --short=7 "v4.3.0:stack.txt")
      _a_blob=$(git -C "$MASTODON_DIR" rev-parse --short=7 "uri/v4.3.0/uri1.0/a:stack.txt")

      When call cmd_collapse "v4.3.0" "uri1.0" "c" "$MASTODON_DIR" --recursive
      The status should be success
      The output should include "collapse 완료"
      The contents of file "${_patch_dir}/b.patch" should include "b-extra"
      The contents of file "${_patch_dir}/b.patch" should include "index ${_tag_blob}.."
      The contents of file "${_patch_dir}/b.patch" should not include "index ${_a_blob}.."
      The contents of file "${_patch_dir}/b.patch" should not include "a-two"
      The contents of file "${_patch_dir}/c.patch" should include "c-original"
      The contents of file "${_patch_dir}/c.patch" should not include "b-extra"
    End

    It '비재귀 collapse는 의존 패치 변경 감지 시 전체를 보존한다'
      git -C "$MASTODON_DIR" checkout "uri/v4.3.0/uri1.0/b" >/dev/null 2>&1
      printf 'one\na-two\nthree\nfour\nfive\nsix\nseven\neight\nnine\nb-ten\neleven\ntwelve\nb-changed\n' > "${MASTODON_DIR}/stack.txt"
      git -C "$MASTODON_DIR" add stack.txt >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Change B" >/dev/null 2>&1

      _a_before=$(cksum "${_patch_dir}/a.patch")
      _b_before=$(cksum "${_patch_dir}/b.patch")
      _c_before=$(cksum "${_patch_dir}/c.patch")
      _manifest_before=$(cksum "${_patch_dir}/manifest.yaml")
      _head_before=$(git -C "$MASTODON_DIR" rev-parse HEAD)
      _a_tip_before=$(git -C "$MASTODON_DIR" rev-parse "uri/v4.3.0/uri1.0/a")
      _b_tip_before=$(git -C "$MASTODON_DIR" rev-parse "uri/v4.3.0/uri1.0/b")
      _c_tip_before=$(git -C "$MASTODON_DIR" rev-parse "uri/v4.3.0/uri1.0/c")

      When call cmd_collapse "v4.3.0" "uri1.0" "c" "$MASTODON_DIR"
      The status should be failure
      The output should include "임시 Git clone"
      The stderr should include "b"
      The stderr should include "--recursive"
      The value "$(cksum "${_patch_dir}/a.patch")" should eq "$_a_before"
      The value "$(cksum "${_patch_dir}/b.patch")" should eq "$_b_before"
      The value "$(cksum "${_patch_dir}/c.patch")" should eq "$_c_before"
      The value "$(cksum "${_patch_dir}/manifest.yaml")" should eq "$_manifest_before"
      The value "$(git -C "$MASTODON_DIR" rev-parse HEAD)" should eq "$_head_before"
      The value "$(git -C "$MASTODON_DIR" rev-parse "uri/v4.3.0/uri1.0/a")" should eq "$_a_tip_before"
      The value "$(git -C "$MASTODON_DIR" rev-parse "uri/v4.3.0/uri1.0/b")" should eq "$_b_tip_before"
      The value "$(git -C "$MASTODON_DIR" rev-parse "uri/v4.3.0/uri1.0/c")" should eq "$_c_tip_before"
    End

    It 'rebase 충돌 시 패치와 원본 브랜치를 보존한다'
      git -C "$MASTODON_DIR" checkout "uri/v4.3.0/uri1.0/b" >/dev/null 2>&1
      printf 'one\nb-requires-a\nthree\nfour\nfive\nsix\nseven\neight\nnine\nb-ten\neleven\ntwelve\n' > "${MASTODON_DIR}/stack.txt"
      git -C "$MASTODON_DIR" add stack.txt >/dev/null 2>&1
      git -C "$MASTODON_DIR" commit -m "Make B require A" >/dev/null 2>&1

      _b_before=$(cksum "${_patch_dir}/b.patch")
      _head_before=$(git -C "$MASTODON_DIR" rev-parse HEAD)
      _b_tip_before=$(git -C "$MASTODON_DIR" rev-parse "uri/v4.3.0/uri1.0/b")

      When call cmd_collapse "v4.3.0" "uri1.0" "c" "$MASTODON_DIR" --recursive
      The status should be failure
      The output should include "임시 Git clone"
      The stderr should include "rebase"
      The value "$(cksum "${_patch_dir}/b.patch")" should eq "$_b_before"
      The value "$(git -C "$MASTODON_DIR" rev-parse HEAD)" should eq "$_head_before"
      The value "$(git -C "$MASTODON_DIR" rev-parse "uri/v4.3.0/uri1.0/b")" should eq "$_b_tip_before"
    End
  End
End
