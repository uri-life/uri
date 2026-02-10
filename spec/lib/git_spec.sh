#!/bin/sh
# git_spec.sh - lib/git.sh 테스트

Describe 'lib/git.sh'
  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/git.sh"

  Describe '순수 문자열 함수'
    Describe 'uri_branch_name()'
      It 'uri feature 브랜치 이름을 생성한다'
        When call uri_branch_name "v4.3.0" "uri1.0" "custom_emoji"
        The output should eq "uri/v4.3.0/uri1.0/custom_emoji"
      End
    End

    Describe 'uri_version_branch_name()'
      It 'uri 버전 브랜치 이름을 생성한다'
        When call uri_version_branch_name "v4.3.0" "uri1.0"
        The output should eq "uri/v4.3.0/uri1.0"
      End
    End
  End

  Describe 'Git 리포지토리 함수'
    Skip if "git이 설치되어 있지 않습니다" has_no_git

    setup_repo() {
      REPO_DIR="${TEST_TMPDIR}/repo"
      create_test_git_repo "$REPO_DIR"
    }
    BeforeEach 'setup_repo'

    Describe 'git_is_repo()'
      It 'Git 리포지토리이면 true를 반환한다'
        When call git_is_repo "$REPO_DIR"
        The status should be success
      End

      It 'Git 리포지토리가 아니면 false를 반환한다'
        When call git_is_repo "$TEST_TMPDIR"
        The status should be failure
      End
    End

    Describe 'git_require_repo()'
      It 'Git 리포지토리가 아니면 die한다'
        When run script -e -c ". '$LIB_DIR/common.sh'; . '$LIB_DIR/git.sh'; git_require_repo '$TEST_TMPDIR'"
        The status should be failure
        The stderr should include 'Git 리포지토리가 아닙니다'
      End
    End

    Describe 'git_is_clean()'
      It '깨끗한 워킹 트리는 true를 반환한다'
        When call git_is_clean "$REPO_DIR"
        The status should be success
      End

      It '변경 사항이 있으면 false를 반환한다'
        echo "modified" >> "${REPO_DIR}/README.md"
        When call git_is_clean "$REPO_DIR"
        The status should be failure
      End
    End

    Describe 'git_ensure_clean()'
      It '깨끗하면 성공한다'
        When call git_ensure_clean "$REPO_DIR"
        The status should be success
      End
    End

    Describe 'git_create_branch() / git_branch_exists()'
      It '브랜치를 생성하고 확인할 수 있다'
        git_create_branch "$REPO_DIR" "test-branch"
        When call git_branch_exists "$REPO_DIR" "test-branch"
        The status should be success
      End
    End

    Describe 'git_create_branch_at()'
      It '체크아웃 없이 브랜치를 생성한다'
        git_create_branch_at "$REPO_DIR" "at-branch"
        When call git_current_branch "$REPO_DIR"
        The output should eq "main"
      End

      It '생성된 브랜치가 존재한다'
        git_create_branch_at "$REPO_DIR" "at-branch2"
        When call git_branch_exists "$REPO_DIR" "at-branch2"
        The status should be success
      End
    End

    Describe 'git_checkout_branch()'
      It '브랜치로 체크아웃할 수 있다'
        git_create_branch_at "$REPO_DIR" "switch-branch"
        git_checkout_branch "$REPO_DIR" "switch-branch"
        When call git_current_branch "$REPO_DIR"
        The output should eq "switch-branch"
      End
    End

    Describe 'git_current_branch()'
      It '현재 브랜치명을 반환한다'
        When call git_current_branch "$REPO_DIR"
        The output should eq "main"
      End
    End

    Describe 'git_current_commit()'
      It '커밋 해시를 반환한다'
        When call git_current_commit "$REPO_DIR"
        The output should match pattern "[0-9a-f]*"
        The length of output should eq 40
      End
    End

    Describe 'git_branch_exists()'
      It '존재하지 않는 브랜치는 false를 반환한다'
        When call git_branch_exists "$REPO_DIR" "nonexistent"
        The status should be failure
      End
    End

    Describe 'git_delete_branch()'
      It '브랜치를 삭제할 수 있다'
        git_create_branch_at "$REPO_DIR" "del-branch"
        git_delete_branch "$REPO_DIR" "del-branch"
        When call git_branch_exists "$REPO_DIR" "del-branch"
        The status should be failure
      End
    End

    Describe 'git_commit_count()'
      It '커밋 범위의 커밋 수를 반환한다'
        # main에 추가 커밋 생성
        echo "extra" > "${REPO_DIR}/extra.txt"
        git -C "$REPO_DIR" add . >/dev/null 2>&1
        git -C "$REPO_DIR" commit -m "second" >/dev/null 2>&1
        _first=$(git -C "$REPO_DIR" rev-list --max-parents=0 HEAD)
        When call git_commit_count "$REPO_DIR" "${_first}..HEAD"
        The output should eq "1"
      End
    End

    Describe 'git_has_diff()'
      It '동일한 ref는 diff가 없다'
        When call git_has_diff "$REPO_DIR" "HEAD" "HEAD"
        The status should be failure
      End

      It '다른 ref는 diff가 있다'
        echo "change" > "${REPO_DIR}/new.txt"
        git -C "$REPO_DIR" add . >/dev/null 2>&1
        git -C "$REPO_DIR" commit -m "change" >/dev/null 2>&1
        _first=$(git -C "$REPO_DIR" rev-list --max-parents=0 HEAD)
        When call git_has_diff "$REPO_DIR" "$_first" "HEAD"
        The status should be success
      End
    End

    Describe 'git_am_in_progress()'
      It 'rebase-apply가 없으면 false를 반환한다'
        When call git_am_in_progress "$REPO_DIR"
        The status should be failure
      End
    End

    Describe 'git_format_patch()'
      It '패치를 추출하고 From 해시를 0-padding한다'
        # 커밋 추가
        echo "patch-content" > "${REPO_DIR}/patched.txt"
        git -C "$REPO_DIR" add . >/dev/null 2>&1
        git -C "$REPO_DIR" commit -m "test patch" >/dev/null 2>&1
        _first=$(git -C "$REPO_DIR" rev-list --max-parents=0 HEAD)
        _output="${TEST_TMPDIR}/output.patch"
        When call git_format_patch "$REPO_DIR" "${_first}..HEAD" "$_output"
        The path "$_output" should be exist
        The contents of file "$_output" should include "patch-content"
        # From 라인의 해시가 0으로 대체되었는지 확인
        The contents of file "$_output" should match pattern "*From 0000000*"
      End
    End

    Describe 'git_am()'
      It '패치를 적용할 수 있다'
        # 기본 리포에서 패치 생성
        echo "am-test" > "${REPO_DIR}/am-test.txt"
        git -C "$REPO_DIR" add . >/dev/null 2>&1
        git -C "$REPO_DIR" commit -m "am test commit" >/dev/null 2>&1
        _first=$(git -C "$REPO_DIR" rev-list --max-parents=0 HEAD)
        _patch="${TEST_TMPDIR}/am-test.patch"
        git -C "$REPO_DIR" format-patch --stdout "${_first}..HEAD" > "$_patch"

        # 다른 리포에 적용
        TARGET="${TEST_TMPDIR}/target"
        create_test_git_repo "$TARGET"
        When call git_am "$TARGET" "$_patch"
        The status should be success
        The output should include "Applying"
        The path "${TARGET}/am-test.txt" should be exist
      End
    End
  End
End
