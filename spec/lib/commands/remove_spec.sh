#!/bin/sh
# remove_spec.sh - lib/commands/remove.sh 테스트

Describe 'lib/commands/remove.sh'
  Skip if "yq가 설치되어 있지 않습니다" has_no_yq

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"
  Include "$LIB_DIR/state.sh"
  Include "$LIB_DIR/commands/init.sh"
  Include "$LIB_DIR/commands/add.sh"
  Include "$LIB_DIR/commands/remove.sh"

  setup_with_features() {
    cd "$TEST_TMPDIR"
    cmd_init "v4.3.0" >/dev/null 2>&1
    URI_ROOT="$TEST_TMPDIR"
    export URI_ROOT
    cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
    cmd_add "v4.3.0" "uri1.0" "base" >/dev/null 2>&1 || true
    cmd_add "v4.3.0" "uri1.0" "child" --dependencies "base" >/dev/null 2>&1 || true
    cmd_add "v4.3.0" "uri1.0" "independent" >/dev/null 2>&1 || true
  }
  BeforeEach 'setup_with_features'

  Describe 'feature 제거'
    It '-f 옵션으로 feature를 제거할 수 있다'
      cmd_remove "v4.3.0" "uri1.0" "independent" -f >/dev/null 2>&1 || true
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      When call yaml_has "$_manifest" ".features.independent"
      The status should be failure
    End

    It '패치 파일도 삭제된다'
      cmd_remove "v4.3.0" "uri1.0" "independent" -f >/dev/null 2>&1 || true
      When call test -f "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/independent.patch"
      The status should be failure
    End

    It '의존하는 feature가 있어도 -f로 강제 삭제 가능'
      When call cmd_remove "v4.3.0" "uri1.0" "base" -f
      The output should include "base"
      The stderr should include "의존합니다"
      The status should be success
    End
  End

  Describe 'uri 버전 제거'
    It '-f 옵션으로 uri 버전을 제거할 수 있다'
      cmd_remove "v4.3.0" "uri1.0" -f >/dev/null 2>&1 || true
      When call test -d "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0"
      The status should be failure
    End
  End

  Describe 'Mastodon 버전 제거'
    It '-f 옵션으로 Mastodon 버전을 제거할 수 있다'
      cmd_remove "v4.3.0" -f >/dev/null 2>&1 || true
      When call test -d "${TEST_TMPDIR}/versions/v4.3.0"
      The status should be failure
    End
  End

  Describe 'remove_usage()'
    It '도움말을 출력한다'
      When call remove_usage
      The output should include "사용법"
      The output should include "uri remove"
    End
  End
End
