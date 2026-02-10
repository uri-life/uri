#!/bin/sh
# yaml_spec.sh - lib/yaml.sh 테스트

Describe 'lib/yaml.sh'
  Skip if "yq가 설치되어 있지 않습니다" has_no_yq

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"

  Describe 'yaml_create_empty()'
    It '빈 YAML 파일을 생성한다'
      _file="${TEST_TMPDIR}/empty.yaml"
      When call yaml_create_empty "$_file"
      The contents of file "$_file" should eq "---"
    End
  End

  Describe 'yaml_create()'
    It 'key-value YAML 파일을 생성한다'
      _file="${TEST_TMPDIR}/created.yaml"
      When call yaml_create "$_file" "name" "test"
      The contents of file "$_file" should eq "name: test"
    End
  End

  Describe 'yaml_set() / yaml_get()'
    setup() {
      _file="${TEST_TMPDIR}/test.yaml"
      echo "---" > "$_file"
    }
    BeforeEach 'setup'

    It '값을 쓰고 읽을 수 있다'
      yaml_set "$_file" ".key" "value"
      When call yaml_get "$_file" ".key"
      The output should eq "value"
    End

    It '중첩된 경로에 값을 쓸 수 있다'
      yaml_set "$_file" ".parent.child" "nested"
      When call yaml_get "$_file" ".parent.child"
      The output should eq "nested"
    End

    It '값을 덮어쓸 수 있다'
      yaml_set "$_file" ".key" "old"
      yaml_set "$_file" ".key" "new"
      When call yaml_get "$_file" ".key"
      The output should eq "new"
    End
  End

  Describe 'yaml_set_raw()'
    It 'raw 값(따옴표 없이)을 쓸 수 있다'
      _file="${TEST_TMPDIR}/raw.yaml"
      echo "---" > "$_file"
      yaml_set_raw "$_file" ".count" "42"
      When call yaml_get "$_file" ".count"
      The output should eq "42"
    End

    It '빈 배열을 raw로 설정할 수 있다'
      _file="${TEST_TMPDIR}/raw.yaml"
      echo "---" > "$_file"
      yaml_set_raw "$_file" ".items" "[]"
      When call yaml_array_len "$_file" ".items"
      The output should eq "0"
    End
  End

  Describe 'yaml_append()'
    It '배열에 값을 추가할 수 있다'
      _file="${TEST_TMPDIR}/arr.yaml"
      echo "items: []" > "$_file"
      yaml_append "$_file" ".items" "first"
      yaml_append "$_file" ".items" "second"
      When call yaml_array_len "$_file" ".items"
      The output should eq "2"
    End
  End

  Describe 'yaml_delete()'
    It '경로를 삭제할 수 있다'
      _file="${TEST_TMPDIR}/del.yaml"
      echo "a: 1" > "$_file"
      echo "b: 2" >> "$_file"
      yaml_delete "$_file" ".a"
      When call yaml_has "$_file" ".a"
      The status should be failure
    End
  End

  Describe 'yaml_keys()'
    It '객체의 키 목록을 반환한다'
      _file="${TEST_TMPDIR}/keys.yaml"
      printf "alpha: 1\nbeta: 2\ngamma: 3\n" > "$_file"
      When call yaml_keys "$_file" "."
      The line 1 should eq "alpha"
      The line 2 should eq "beta"
      The line 3 should eq "gamma"
    End
  End

  Describe 'yaml_has()'
    setup() {
      _file="${TEST_TMPDIR}/has.yaml"
      printf "existing: value\nnested:\n  child: yes\n" > "$_file"
    }
    BeforeEach 'setup'

    It '존재하는 경로는 true를 반환한다'
      When call yaml_has "$_file" ".existing"
      The status should be success
    End

    It '존재하지 않는 경로는 false를 반환한다'
      When call yaml_has "$_file" ".nonexistent"
      The status should be failure
    End

    It '중첩된 경로도 확인할 수 있다'
      When call yaml_has "$_file" ".nested.child"
      The status should be success
    End
  End

  Describe 'yaml_array_len()'
    It '배열 길이를 반환한다'
      _file="${TEST_TMPDIR}/len.yaml"
      printf "items:\n  - a\n  - b\n  - c\n" > "$_file"
      When call yaml_array_len "$_file" ".items"
      The output should eq "3"
    End

    It '빈 배열은 0을 반환한다'
      _file="${TEST_TMPDIR}/len.yaml"
      echo "items: []" > "$_file"
      When call yaml_array_len "$_file" ".items"
      The output should eq "0"
    End
  End

  Describe 'yaml_array_items()'
    It '배열 요소를 줄바꿈 구분으로 반환한다'
      _file="${TEST_TMPDIR}/items.yaml"
      printf "items:\n  - alpha\n  - beta\n" > "$_file"
      When call yaml_array_items "$_file" ".items"
      The line 1 should eq "alpha"
      The line 2 should eq "beta"
    End
  End

  Describe 'yaml_merge()'
    It 'overlay가 base를 덮어쓴다'
      _base="${TEST_TMPDIR}/base.yaml"
      _overlay="${TEST_TMPDIR}/overlay.yaml"
      printf "a: 1\nb: 2\n" > "$_base"
      printf "b: 99\nc: 3\n" > "$_overlay"
      When call yaml_merge "$_base" "$_overlay"
      The output should include "b: 99"
      The output should include "c: 3"
    End
  End

  Describe 'feature 헬퍼 함수'
    setup() {
      _file="${TEST_TMPDIR}/feat.yaml"
      cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_file"
    }
    BeforeEach 'setup'

    Describe 'yaml_list_features()'
      It 'feature 키 목록을 반환한다'
        When call yaml_list_features "$_file"
        The output should include "base"
        The output should include "custom_emoji"
        The output should include "theme"
      End
    End

    Describe 'yaml_get_feature_name()'
      It 'feature의 이름을 반환한다'
        When call yaml_get_feature_name "$_file" "custom_emoji"
        The output should eq "커스텀 이모지"
      End
    End

    Describe 'yaml_get_feature_description()'
      It 'feature의 설명을 반환한다'
        When call yaml_get_feature_description "$_file" "custom_emoji"
        The output should eq "이모지 기능 확장"
      End
    End

    Describe 'yaml_get_feature_dependencies()'
      It '의존성 목록을 반환한다'
        When call yaml_get_feature_dependencies "$_file" "custom_emoji"
        The output should eq "base"
      End

      It '의존성이 없으면 빈 결과를 반환한다'
        When call yaml_get_feature_dependencies "$_file" "theme"
        The status should be success
      End
    End

    Describe 'yaml_get_inherits()'
      It 'inherits 값을 반환한다'
        _inh="${TEST_TMPDIR}/inh.yaml"
        printf "inherits: \"uri1.0\"\nfeatures: {}\n" > "$_inh"
        When call yaml_get_inherits "$_inh"
        The output should eq "uri1.0"
      End

      It 'inherits가 없으면 빈 문자열을 반환한다'
        When call yaml_get_inherits "$_file"
        The output should eq ""
      End
    End

    Describe 'yaml_get_features_json()'
      It 'features를 JSON으로 출력한다'
        When call yaml_get_features_json "$_file"
        The output should include "base"
        The output should include "custom_emoji"
      End
    End
  End
End
