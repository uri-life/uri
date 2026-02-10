#!/bin/sh
# common_spec.sh - lib/common.sh 테스트

Describe 'lib/common.sh'
  Include "$LIB_DIR/common.sh"

  Describe 'die()'
    It '에러 메시지를 stderr에 출력하고 종료 코드 1을 반환한다'
      When run script -e -c ". '$LIB_DIR/common.sh'; die '테스트 에러'"
      The status should be failure
      The stderr should include '테스트 에러'
    End
  End

  Describe 'warn()'
    It '경고 메시지를 stderr에 출력한다'
      When call warn '경고 메시지'
      The stderr should include '경고 메시지'
    End
  End

  Describe 'info()'
    It '정보 메시지를 stdout에 출력한다'
      When call info '정보 메시지'
      The output should include '정보 메시지'
    End
  End

  Describe 'success()'
    It '성공 메시지를 stdout에 출력한다'
      When call success '성공 메시지'
      The output should include '성공 메시지'
    End
  End

  Describe 'require_cmd()'
    It '존재하는 명령어는 성공한다'
      When call require_cmd "sh"
      The status should be success
    End

    It '존재하지 않는 명령어는 실패한다'
      When run script -e -c ". '$LIB_DIR/common.sh'; require_cmd 'nonexistent_cmd_xyz'"
      The status should be failure
      The stderr should include 'nonexistent_cmd_xyz'
    End
  End

  Describe 'version_dir()'
    It 'URI_ROOT 기반으로 버전 디렉터리 경로를 반환한다'
      URI_ROOT="/tmp/test"
      When call version_dir "v4.3.0"
      The output should eq "/tmp/test/versions/v4.3.0"
    End
  End

  Describe 'uri_version_dir()'
    It 'URI_ROOT 기반으로 uri 버전 디렉터리 경로를 반환한다'
      URI_ROOT="/tmp/test"
      When call uri_version_dir "v4.3.0" "uri1.0"
      The output should eq "/tmp/test/versions/v4.3.0/patches/uri1.0"
    End
  End

  Describe 'resolve_path()'
    It '디렉터리의 절대 경로를 반환한다'
      When call resolve_path "$TEST_TMPDIR"
      The output should eq "$TEST_TMPDIR"
    End

    It '파일의 절대 경로를 반환한다'
      touch "${TEST_TMPDIR}/testfile"
      When call resolve_path "${TEST_TMPDIR}/testfile"
      The output should eq "${TEST_TMPDIR}/testfile"
    End

    It '상대 경로를 절대 경로로 변환한다'
      When call resolve_path "."
      The output should not eq "."
      The output should start with "/"
    End
  End

  Describe 'find_uri_root()'
    It 'manifest.yaml이 있는 디렉터리를 찾는다'
      touch "${TEST_TMPDIR}/manifest.yaml"
      mkdir -p "${TEST_TMPDIR}/subdir"
      cd "${TEST_TMPDIR}/subdir"
      When call find_uri_root
      The output should eq "$TEST_TMPDIR"
      The status should be success
    End

    It 'manifest.yaml이 없으면 실패한다'
      cd "$TEST_TMPDIR"
      When call find_uri_root
      The status should be failure
    End
  End

  Describe 'require_uri_root()'
    It 'manifest.yaml이 있으면 URI_ROOT를 설정한다'
      touch "${TEST_TMPDIR}/manifest.yaml"
      cd "$TEST_TMPDIR"
      When call require_uri_root
      The status should be success
      The variable URI_ROOT should eq "$TEST_TMPDIR"
    End
  End

  Describe 'set_uri_root_if_exists()'
    It 'manifest.yaml이 있으면 성공한다'
      touch "${TEST_TMPDIR}/manifest.yaml"
      cd "$TEST_TMPDIR"
      When call set_uri_root_if_exists
      The status should be success
    End

    It 'manifest.yaml이 없으면 실패하되 die하지 않는다'
      cd "$TEST_TMPDIR"
      When call set_uri_root_if_exists
      The status should be failure
    End
  End

  Describe 'require_file()'
    It '파일이 존재하면 성공한다'
      touch "${TEST_TMPDIR}/exists.txt"
      When call require_file "${TEST_TMPDIR}/exists.txt"
      The status should be success
    End

    It '파일이 없으면 die한다'
      When run script -e -c ". '$LIB_DIR/common.sh'; require_file '${TEST_TMPDIR}/nofile.txt'"
      The status should be failure
      The stderr should include "파일을 찾을 수 없습니다"
    End
  End

  Describe 'require_dir()'
    It '디렉터리가 존재하면 성공한다'
      When call require_dir "$TEST_TMPDIR"
      The status should be success
    End

    It '디렉터리가 없으면 die한다'
      When run script -e -c ". '$LIB_DIR/common.sh'; require_dir '${TEST_TMPDIR}/nodir'"
      The status should be failure
      The stderr should include "디렉터리를 찾을 수 없습니다"
    End
  End

  Describe 'make_temp() / cleanup_temp()'
    It '임시 파일을 생성한다'
      When call make_temp
      The output should not be blank
    End

    It 'cleanup_temp로 임시 파일을 삭제한다'
      _tmpfile=$(mktemp)
      _TEMP_FILES="${_TEMP_FILES} ${_tmpfile}"
      echo "test" > "$_tmpfile"
      cleanup_temp
      When call test -f "$_tmpfile"
      The status should be failure
    End
  End
End
