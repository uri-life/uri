#!/bin/sh
# list_spec.sh - lib/commands/list.sh 테스트

Describe 'lib/commands/list.sh'
  Skip if "yq가 설치되어 있지 않습니다" has_no_yq

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"
  Include "$LIB_DIR/state.sh"
  Include "$LIB_DIR/commands/init.sh"
  Include "$LIB_DIR/commands/add.sh"
  Include "$LIB_DIR/commands/list.sh"

  setup_patchset() {
    cd "$TEST_TMPDIR"
    cmd_init "v4.3.0" >/dev/null 2>&1
    URI_ROOT="$TEST_TMPDIR"
    export URI_ROOT
    cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
    cmd_add "v4.3.0" "uri1.0" "base" --name "기본" >/dev/null 2>&1 || true
    cmd_add "v4.3.0" "uri1.0" "theme" --name "테마" >/dev/null 2>&1 || true
  }
  BeforeEach 'setup_patchset'

  Describe 'Mastodon 버전 목록'
    It '버전 목록을 출력한다'
      When call cmd_list
      The output should include "v4.3.0"
    End

    It '여러 버전이 있으면 모두 출력한다'
      cmd_init "v4.4.0" >/dev/null 2>&1
      When call cmd_list
      The output should include "v4.3.0"
      The output should include "v4.4.0"
    End
  End

  Describe 'uri 패치 목록'
    It 'uri 버전 목록을 출력한다'
      When call cmd_list "v4.3.0"
      The output should include "uri1.0"
    End
  End

  Describe 'feature 목록'
    It 'feature 목록을 출력한다'
      When call cmd_list "v4.3.0" "uri1.0"
      The output should include "base"
      The output should include "theme"
    End
  End

  Describe 'list_usage()'
    It '도움말을 출력한다'
      When call list_usage
      The output should include "사용법"
      The output should include "uri list"
    End
  End
End
