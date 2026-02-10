#!/bin/sh
# add_spec.sh - lib/commands/add.sh 테스트

Describe 'lib/commands/add.sh'
  Skip if "yq가 설치되어 있지 않습니다" has_no_yq

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"
  Include "$LIB_DIR/state.sh"
  Include "$LIB_DIR/commands/init.sh"
  Include "$LIB_DIR/commands/add.sh"

  setup_patchset() {
    cd "$TEST_TMPDIR"
    cmd_init "v4.3.0" >/dev/null 2>&1
    URI_ROOT="$TEST_TMPDIR"
    export URI_ROOT
  }
  BeforeEach 'setup_patchset'

  Describe 'uri 버전 추가'
    It 'uri 버전을 추가할 수 있다'
      When call cmd_add "v4.3.0" "uri1.0"
      The status should be success
      The output should include "uri1.0"
      The path "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0" should be directory
      The path "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml" should be exist
    End

    It 'manifest.yaml에 features 섹션이 있다'
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      When call yaml_has "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml" ".features"
      The status should be success
    End

    It '--inherits 옵션으로 상속을 설정할 수 있다'
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.1" --inherits "uri1.0" >/dev/null 2>&1 || true
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
      When call yaml_get_inherits "$_manifest"
      The output should eq "uri1.0"
    End

    It '이미 존재하는 uri 버전은 die한다'
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
      When run script -e -c "
        URI_ROOT='$TEST_TMPDIR'; export URI_ROOT
        . '$LIB_DIR/common.sh'; . '$LIB_DIR/yaml.sh'; . '$LIB_DIR/git.sh'
        . '$LIB_DIR/topsort.sh'; . '$LIB_DIR/inherit.sh'; . '$LIB_DIR/state.sh'
        . '$LIB_DIR/commands/add.sh'
        cmd_add v4.3.0 uri1.0
      "
      The status should be failure
      The stderr should include '이미 존재'
    End
  End

  Describe 'feature 추가'
    setup_uri_version() {
      cmd_add "v4.3.0" "uri1.0" >/dev/null 2>&1 || true
    }
    BeforeEach 'setup_uri_version'

    It 'feature를 추가할 수 있다'
      When call cmd_add "v4.3.0" "uri1.0" "my_feature"
      The status should be success
      The output should include "my_feature"
    End

    It 'manifest에 feature가 추가된다'
      cmd_add "v4.3.0" "uri1.0" "my_feature" >/dev/null 2>&1
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      When call yaml_has "$_manifest" ".features.my_feature"
      The status should be success
    End

    It '빈 패치 파일이 생성된다'
      cmd_add "v4.3.0" "uri1.0" "my_feature" >/dev/null 2>&1 || true
      When call test -f "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/my_feature.patch"
      The status should be success
    End

    It '--name 옵션으로 이름을 설정할 수 있다'
      cmd_add "v4.3.0" "uri1.0" "feat" --name "테스트 기능" >/dev/null 2>&1 || true
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      When call yaml_get_feature_name "$_manifest" "feat"
      The output should eq "테스트 기능"
    End

    It '--description 옵션으로 설명을 설정할 수 있다'
      cmd_add "v4.3.0" "uri1.0" "feat" --description "설명입니다" >/dev/null 2>&1 || true
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      When call yaml_get_feature_description "$_manifest" "feat"
      The output should eq "설명입니다"
    End

    It '--dependencies 옵션으로 의존성을 설정할 수 있다'
      cmd_add "v4.3.0" "uri1.0" "base" >/dev/null 2>&1 || true
      cmd_add "v4.3.0" "uri1.0" "feat" --dependencies "base" >/dev/null 2>&1 || true
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      When call yaml_get_feature_dependencies "$_manifest" "feat"
      The output should include "base"
    End

    It '중복 feature는 die한다'
      cmd_add "v4.3.0" "uri1.0" "dup" >/dev/null 2>&1 || true
      When run script -e -c "
        URI_ROOT='$TEST_TMPDIR'; export URI_ROOT
        . '$LIB_DIR/common.sh'; . '$LIB_DIR/yaml.sh'; . '$LIB_DIR/git.sh'
        . '$LIB_DIR/topsort.sh'; . '$LIB_DIR/inherit.sh'; . '$LIB_DIR/state.sh'
        . '$LIB_DIR/commands/add.sh'
        cmd_add v4.3.0 uri1.0 dup
      "
      The status should be failure
      The stderr should include '이미 존재'
    End
  End

  Describe 'add_usage()'
    It '도움말을 출력한다'
      When call add_usage
      The output should include "사용법"
      The output should include "uri add"
    End
  End
End
