#!/bin/sh
# migrate_spec.sh - lib/commands/migrate.sh 통합 테스트
# 실제 데이터(uri-life/mastodon)를 사용하는 통합 테스트
#
# 실행 방법:
#   1. mastodon 리포지토리 클론 (partial clone OK):
#      git clone --filter=blob:none https://github.com/uri-life/mastodon.git /tmp/mastodon-cache
#   2. 통합 테스트 실행:
#      URI_MASTODON_REPO=/tmp/mastodon-cache URI_INTEGRATION_TEST=1 \
#        shellspec spec/lib/commands/migrate_spec.sh --format documentation

# 통합 테스트 비활성화 확인
integration_tests_disabled() {
  [ "${URI_INTEGRATION_TEST:-}" != "1" ]
}

# mastodon 리포지토리 미설정 확인
mastodon_repo_not_available() {
  [ -z "${URI_MASTODON_REPO:-}" ] || [ ! -d "${URI_MASTODON_REPO:-}" ]
}

Describe 'lib/commands/migrate.sh'
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
  Include "$LIB_DIR/commands/apply.sh"
  Include "$LIB_DIR/commands/migrate.sh"

  Describe 'migrate_usage()'
    It '도움말을 출력한다'
      When call migrate_usage
      The output should include "사용법"
      The output should include "uri migrate"
    End
  End

  Describe '_find_branches_by_prefix() - 통합 테스트'
    Skip if "git이 설치되어 있지 않습니다" has_no_git
    Skip if "통합 테스트가 비활성화되어 있습니다 (URI_INTEGRATION_TEST=1)" integration_tests_disabled
    Skip if "URI_MASTODON_REPO 미설정" mastodon_repo_not_available

    BRANCH_PREFIX="v4.4.12/uri2"

    setup_branch_env() {
      cd "$TEST_TMPDIR" || return 1
      _old_repo="${TEST_TMPDIR}/old_mastodon"
      git init "$_old_repo" >/dev/null 2>&1
      git -C "$_old_repo" config user.email "test@example.com"
      git -C "$_old_repo" config user.name "Test"
      git -C "$_old_repo" commit --allow-empty -m "dummy" >/dev/null 2>&1
      # 캐시 리포의 실제 브랜치 이름을 읽어서 로컬 브랜치를 생성 (객체는 불필요)
      for _rb in $(git -C "$URI_MASTODON_REPO" branch -r --list "origin/${BRANCH_PREFIX}/*" --format='%(refname:short)'); do
        _branch=$(echo "$_rb" | sed 's|^origin/||')
        git -C "$_old_repo" branch "$_branch" >/dev/null 2>&1 || true
      done
    }
    BeforeEach 'setup_branch_env'

    It 'feature 브랜치를 찾아서 이름을 반환한다'
      When call _find_branches_by_prefix "$_old_repo" "$BRANCH_PREFIX"
      The status should be success
      The output should not equal ""
    End

    It '올바른 feature 이름을 추출한다'
      When call _find_branches_by_prefix "$_old_repo" "$BRANCH_PREFIX"
      The output should include "robots"
    End
  End

  Describe 'cmd_migrate() - 통합 테스트'
    Skip if "yq가 설치되어 있지 않습니다" has_no_yq
    Skip if "git이 설치되어 있지 않습니다" has_no_git
    Skip if "통합 테스트가 비활성화되어 있습니다 (URI_INTEGRATION_TEST=1)" integration_tests_disabled
    Skip if "URI_MASTODON_REPO 미설정" mastodon_repo_not_available

    MASTODON_VERSION="v4.4.12"
    BRANCH_PREFIX="v4.4.12/uri2"
    URI_MINOR="11"

    setup_migrate_env() {
      cd "$TEST_TMPDIR" || return 1

      # 원본 GitHub URL 추출 (partial clone 대응)
      _github_url=$(git -C "$URI_MASTODON_REPO" remote get-url origin 2>/dev/null)

      # old_repo: 기존 브랜치 기반 리포지토리
      # --reference로 캐시 객체 공유, --filter로 blob 지연 로드
      _old_repo="${TEST_TMPDIR}/old_mastodon"
      git clone --filter=blob:none --no-checkout \
        --reference "$URI_MASTODON_REPO" "$_github_url" "$_old_repo" >/dev/null 2>&1
      git -C "$_old_repo" config user.email "test@example.com"
      git -C "$_old_repo" config user.name "Test"
      git -C "$_old_repo" config tag.gpgSign false
      git -C "$_old_repo" config commit.gpgSign false
      git -C "$_old_repo" checkout "$MASTODON_VERSION" >/dev/null 2>&1

      # 처음 2개 feature만 로컬 브랜치로 생성 (테스트 속도 최적화)
      _selected=""
      _count=0
      for _rb in $(git -C "$_old_repo" branch -r --list "origin/${BRANCH_PREFIX}/*" --format='%(refname:short)' | head -2); do
        _feat=$(echo "$_rb" | sed "s|^origin/${BRANCH_PREFIX}/||")
        git -C "$_old_repo" branch "${BRANCH_PREFIX}/${_feat}" "$_rb" >/dev/null 2>&1 || true
        _selected="$_selected $_feat"
        _count=$((_count + 1))
      done
      SELECTED_FEATURES=$(echo "$_selected" | sed 's/^ *//')

      # new_repo: 마이그레이션 대상 리포지토리
      _new_repo="${TEST_TMPDIR}/new_mastodon"
      git clone --filter=blob:none --no-checkout \
        --reference "$URI_MASTODON_REPO" "$_github_url" "$_new_repo" >/dev/null 2>&1
      git -C "$_new_repo" config user.email "test@example.com"
      git -C "$_new_repo" config user.name "Test"
      git -C "$_new_repo" config tag.gpgSign false
      git -C "$_new_repo" config commit.gpgSign false
      git -C "$_new_repo" checkout "$MASTODON_VERSION" >/dev/null 2>&1
    }
    BeforeEach 'setup_migrate_env'

    It '실제 데이터로 마이그레이션을 수행하고 올바른 결과를 생성한다'
      When call cmd_migrate "$_old_repo" "$BRANCH_PREFIX" "$URI_MINOR" "$_new_repo"
      The status should be success
      The output should include "마이그레이션 완료"
      The output should include "성공적으로 적용"
      The path "${TEST_TMPDIR}/versions/${MASTODON_VERSION}/patches/uri2.${URI_MINOR}" should be exist
    End
  End
End
