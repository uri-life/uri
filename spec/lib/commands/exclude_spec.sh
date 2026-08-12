#!/bin/sh
# exclude_spec.sh - lib/commands/exclude.sh 테스트

Describe 'lib/commands/exclude.sh'
  Skip if "yq가 설치되어 있지 않습니다" has_no_yq

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"
  Include "$LIB_DIR/state.sh"
  Include "$LIB_DIR/commands/exclude.sh"

  setup_inherited() {
    cd "$TEST_TMPDIR"
    create_test_inherited_patchset "$TEST_TMPDIR"
    URI_ROOT="$TEST_TMPDIR"
    export URI_ROOT
    CHILD_MANIFEST="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
    PARENT_THEME_PATCH="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/theme.patch"
    export CHILD_MANIFEST PARENT_THEME_PATCH
  }
  BeforeEach 'setup_inherited'

  run_exclusion_command() {
    _rec_command="$1"
    shift
    ("$_rec_command" "$@")
  }

  Describe 'exclude'
    It '활성 상속 feature를 제외한다'
      cmd_exclude "v4.3.0" "uri1.1" "theme" >/dev/null
      When call yaml_excludes_feature "$CHILD_MANIFEST" "theme"
      The status should be success
    End

    It '상속된 패치 파일을 변경하지 않는다'
      _before=$(cksum "$PARENT_THEME_PATCH")
      cmd_exclude "v4.3.0" "uri1.1" "theme" >/dev/null
      When call cksum "$PARENT_THEME_PATCH"
      The output should eq "$_before"
    End

    It '현재 manifest가 선언한 feature를 거부한다'
      When call run_exclusion_command cmd_exclude "v4.3.0" "uri1.1" "extra"
      The status should be failure
      The stderr should include "uri remove"
    End

    It '이미 제외한 feature를 거부한다'
      cmd_exclude "v4.3.0" "uri1.1" "theme" >/dev/null
      When call run_exclusion_command cmd_exclude "v4.3.0" "uri1.1" "theme"
      The status should be failure
      The stderr should include "이미 제외"
    End

    It '존재하지 않는 feature를 거부한다'
      When call run_exclusion_command cmd_exclude "v4.3.0" "uri1.1" "missing"
      The status should be failure
      The stderr should include "활성화된 상속 feature"
    End

    It '남은 feature의 의존성을 끊는 제외는 manifest를 변경하지 않는다'
      _manifest_before=$(cksum "$CHILD_MANIFEST")
      _patch_before=$(cksum "$PARENT_THEME_PATCH")
      When call run_exclusion_command cmd_exclude "v4.3.0" "uri1.1" "base"
      The status should be failure
      The stderr should include 'extra.dependencies -> base'
      The value "$(cksum "$CHILD_MANIFEST")" should eq "$_manifest_before"
      The value "$(cksum "$PARENT_THEME_PATCH")" should eq "$_patch_before"
    End
  End

  Describe 'include'
    It '현재 manifest의 제외를 해제한다'
      cmd_exclude "v4.3.0" "uri1.1" "theme" >/dev/null
      cmd_include "v4.3.0" "uri1.1" "theme" >/dev/null
      When call yaml_excludes_feature "$CHILD_MANIFEST" "theme"
      The status should be failure
    End

    It '현재 manifest가 직접 제외하지 않은 feature를 거부한다'
      When call run_exclusion_command cmd_include "v4.3.0" "uri1.1" "theme"
      The status should be failure
      The stderr should include "현재 manifest에서 제외된 feature가 아닙니다"
    End

    It '조상 manifest의 제외를 해제하지 않는다'
      yaml_set_raw "$CHILD_MANIFEST" ".excludes" '["theme"]'
      _grandchild_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.2"
      mkdir -p "$_grandchild_dir"
      printf 'inherits: uri1.1\nfeatures: {}\n' > "${_grandchild_dir}/manifest.yaml"
      When call run_exclusion_command cmd_include "v4.3.0" "uri1.2" "theme"
      The status should be failure
      The stderr should include "현재 manifest에서 제외된 feature가 아닙니다"
    End

    It '해제 후 의존성이 끊기면 manifest를 변경하지 않는다'
      _parent="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      yaml_set_raw "$_parent" ".features.dependent" '{"name": "종속", "description": "", "dependencies": ["base"]}'
      yaml_set_raw "$CHILD_MANIFEST" ".features" '{}'
      yaml_set_raw "$CHILD_MANIFEST" ".excludes" '["base", "dependent"]'
      When call run_exclusion_command cmd_include "v4.3.0" "uri1.1" "dependent"
      The status should be failure
      The stderr should include 'dependent.dependencies -> base'
      The contents of file "$CHILD_MANIFEST" should include "dependent"
    End
  End

  Describe 'usage'
    It 'exclude/include 도움말을 출력한다'
      _exclude=$(exclude_usage)
      _include=$(include_usage)
      When call printf '%s\n%s\n' "$_exclude" "$_include"
      The output should include "uri exclude"
      The output should include "uri include"
    End
  End
End
