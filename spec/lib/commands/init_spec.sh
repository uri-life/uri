#!/bin/sh
# init_spec.sh - lib/commands/init.sh 테스트

Describe 'lib/commands/init.sh'
  Skip if "yq가 설치되어 있지 않습니다" has_no_yq

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"
  Include "$LIB_DIR/state.sh"
  Include "$LIB_DIR/commands/init.sh"

  Describe 'cmd_init()'
    It '패치 세트를 초기화한다'
      cd "$TEST_TMPDIR"
      When call cmd_init
      The status should be success
      The output should include "초기화"
      The path "${TEST_TMPDIR}/manifest.yaml" should be exist
      The path "${TEST_TMPDIR}/versions" should be directory
    End

    It 'manifest.yaml에 upstream이 포함된다'
      cd "$TEST_TMPDIR"
      cmd_init >/dev/null 2>&1
      When call cat "${TEST_TMPDIR}/manifest.yaml"
      The output should include "upstream:"
    End

    It '--upstream 옵션으로 upstream URL을 지정할 수 있다'
      cd "$TEST_TMPDIR"
      cmd_init --upstream "https://custom.git" >/dev/null 2>&1
      When call cat "${TEST_TMPDIR}/manifest.yaml"
      The output should include "https://custom.git"
    End

    It 'Mastodon 버전과 함께 초기화할 수 있다'
      cd "$TEST_TMPDIR"
      When call cmd_init "v4.3.0"
      The status should be success
      The output should include "초기화"
      The path "${TEST_TMPDIR}/versions/v4.3.0" should be directory
      The path "${TEST_TMPDIR}/versions/v4.3.0/patches" should be directory
    End

    It '이미 초기화된 상태에서 새 버전을 추가할 수 있다'
      cd "$TEST_TMPDIR"
      cmd_init "v4.3.0" >/dev/null 2>&1
      When call cmd_init "v4.4.0"
      The status should be success
      The output should include "v4.4.0"
      The path "${TEST_TMPDIR}/versions/v4.4.0" should be directory
    End

    It '이미 초기화된 상태에서 버전 없이 실행하면 die한다'
      cd "$TEST_TMPDIR"
      cmd_init >/dev/null 2>&1
      When run script -e -c "
        cd '$TEST_TMPDIR'
        . '$LIB_DIR/common.sh'
        . '$LIB_DIR/yaml.sh'
        . '$LIB_DIR/git.sh'
        . '$LIB_DIR/topsort.sh'
        . '$LIB_DIR/inherit.sh'
        . '$LIB_DIR/state.sh'
        . '$LIB_DIR/commands/init.sh'
        cmd_init
      "
      The status should be failure
      The stderr should include '이미 초기화'
    End
  End

  Describe 'init_usage()'
    It '도움말을 출력한다'
      When call init_usage
      The output should include "사용법"
      The output should include "uri init"
    End
  End
End
