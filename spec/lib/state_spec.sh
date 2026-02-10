#!/bin/sh
# state_spec.sh - lib/state.sh 테스트

Describe 'lib/state.sh'
  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/state.sh"

  Describe 'state_file()'
    It '상태 파일 경로를 반환한다'
      When call state_file "/tmp/repo"
      The output should eq "/tmp/repo/.uri_state"
    End
  End

  Describe 'state_save() / state_get()'
    It 'key-value를 저장하고 읽을 수 있다'
      state_save "$TEST_TMPDIR" "mykey" "myvalue"
      When call state_get "$TEST_TMPDIR" "mykey"
      The output should eq "myvalue"
    End

    It '값을 덮어쓸 수 있다'
      state_save "$TEST_TMPDIR" "key" "old" || true
      state_save "$TEST_TMPDIR" "key" "new" || true
      When call state_get "$TEST_TMPDIR" "key"
      The output should eq "new"
    End

    It '여러 키를 저장할 수 있다'
      state_save "$TEST_TMPDIR" "a" "1"
      state_save "$TEST_TMPDIR" "b" "2"
      When call state_get "$TEST_TMPDIR" "a"
      The output should eq "1"
    End

    It '값에 공백을 포함할 수 있다'
      state_save "$TEST_TMPDIR" "spaced" "hello world"
      When call state_get "$TEST_TMPDIR" "spaced"
      The output should eq "hello world"
    End

    It '존재하지 않는 키는 빈 문자열을 반환한다'
      When call state_get "$TEST_TMPDIR" "nonexistent"
      The output should eq ""
    End
  End

  Describe 'state_delete()'
    It '특정 키를 삭제할 수 있다'
      state_save "$TEST_TMPDIR" "delkey" "value" || true
      state_delete "$TEST_TMPDIR" "delkey" || true
      When call state_get "$TEST_TMPDIR" "delkey"
      The output should eq ""
    End

    It '다른 키에 영향을 주지 않는다'
      state_save "$TEST_TMPDIR" "keep" "kept"
      state_save "$TEST_TMPDIR" "remove" "gone"
      state_delete "$TEST_TMPDIR" "remove"
      When call state_get "$TEST_TMPDIR" "keep"
      The output should eq "kept"
    End
  End

  Describe 'state_clear()'
    It '상태 파일을 삭제한다'
      state_save "$TEST_TMPDIR" "key" "val"
      state_clear "$TEST_TMPDIR"
      When call state_exists "$TEST_TMPDIR"
      The status should be failure
    End
  End

  Describe 'state_exists()'
    It '상태 파일이 있으면 true를 반환한다'
      state_save "$TEST_TMPDIR" "x" "y"
      When call state_exists "$TEST_TMPDIR"
      The status should be success
    End

    It '상태 파일이 없으면 false를 반환한다'
      When call state_exists "$TEST_TMPDIR"
      The status should be failure
    End
  End

  Describe 'state_in_progress()'
    It 'operation 키가 있으면 true를 반환한다'
      state_save "$TEST_TMPDIR" "operation" "expand"
      When call state_in_progress "$TEST_TMPDIR"
      The status should be success
    End

    It 'operation 키가 없으면 false를 반환한다'
      state_save "$TEST_TMPDIR" "other" "value"
      When call state_in_progress "$TEST_TMPDIR"
      The status should be failure
    End
  End

  Describe 'state_increment_index()'
    It '인덱스를 1 증가시킨다'
      state_save "$TEST_TMPDIR" "current_index" "3" || true
      state_increment_index "$TEST_TMPDIR" || true
      When call state_get "$TEST_TMPDIR" "current_index"
      The output should eq "4"
    End

    It '0에서 시작하여 증가시킨다'
      state_save "$TEST_TMPDIR" "current_index" "0" || true
      state_increment_index "$TEST_TMPDIR" || true
      When call state_get "$TEST_TMPDIR" "current_index"
      The output should eq "1"
    End
  End

  Describe 'state_get_completed_features()'
    It '현재 인덱스 전까지의 feature를 반환한다'
      state_save "$TEST_TMPDIR" "features" "a b c d"
      state_save "$TEST_TMPDIR" "current_index" "2"
      When call state_get_completed_features "$TEST_TMPDIR"
      The output should eq "a b"
    End

    It '인덱스가 0이면 빈 결과를 반환한다'
      state_save "$TEST_TMPDIR" "features" "a b c"
      state_save "$TEST_TMPDIR" "current_index" "0"
      When call state_get_completed_features "$TEST_TMPDIR"
      The output should eq ""
    End
  End

  Describe 'state_get_remaining_features()'
    It '현재 인덱스부터의 feature를 반환한다'
      state_save "$TEST_TMPDIR" "features" "a b c d"
      state_save "$TEST_TMPDIR" "current_index" "2"
      When call state_get_remaining_features "$TEST_TMPDIR"
      The output should eq "c d"
    End

    It '인덱스가 0이면 전체를 반환한다'
      state_save "$TEST_TMPDIR" "features" "a b c"
      state_save "$TEST_TMPDIR" "current_index" "0"
      When call state_get_remaining_features "$TEST_TMPDIR"
      The output should eq "a b c"
    End
  End

  Describe 'state_save_expand()'
    Skip if "git이 설치되어 있지 않습니다" has_no_git

    It 'expand 상태를 일괄 저장한다'
      REPO="${TEST_TMPDIR}/repo"
      create_test_git_repo "$REPO"
      state_save_expand "$REPO" "v4.3.0" "uri1.0" "base emoji" "0"
      When call state_get "$REPO" "operation"
      The output should eq "expand"
    End
  End

  Describe 'state_save_collapse()'
    It 'collapse 상태를 일괄 저장한다'
      state_save_collapse "$TEST_TMPDIR" "v4.3.0" "uri1.0" "base emoji" "1"
      When call state_get "$TEST_TMPDIR" "operation"
      The output should eq "collapse"
    End

    It 'features를 저장한다'
      state_save_collapse "$TEST_TMPDIR" "v4.3.0" "uri1.0" "base emoji theme" "0"
      When call state_get "$TEST_TMPDIR" "features"
      The output should eq "base emoji theme"
    End
  End

  Describe 'state_show()'
    It '진행 중인 작업 정보를 출력한다'
      state_save "$TEST_TMPDIR" "operation" "expand"
      state_save "$TEST_TMPDIR" "mastodon_version" "v4.3.0"
      state_save "$TEST_TMPDIR" "uri_version" "uri1.0"
      state_save "$TEST_TMPDIR" "features" "base emoji"
      state_save "$TEST_TMPDIR" "current_index" "0"
      When call state_show "$TEST_TMPDIR"
      The output should include "expand"
      The output should include "v4.3.0"
    End

    It '상태 파일이 없으면 실패한다'
      When call state_show "$TEST_TMPDIR"
      The output should include "진행 중인 작업이 없습니다"
      The status should be failure
    End
  End
End
