#!/bin/sh
# graph_spec.sh - lib/commands/graph.sh 테스트

Describe 'lib/commands/graph.sh'
  Skip if "yq가 설치되어 있지 않습니다" has_no_yq
  Skip if "tsort가 설치되어 있지 않습니다" has_no_tsort

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"
  Include "$LIB_DIR/state.sh"
  Include "$LIB_DIR/commands/graph.sh"

  setup_patchset() {
    create_test_patchset "$TEST_TMPDIR"
    cd "$TEST_TMPDIR"
    URI_ROOT="$TEST_TMPDIR"
    export URI_ROOT
  }
  BeforeEach 'setup_patchset'

  Describe 'cmd_graph()'
    It '기본 tree 형식으로 의존성 그래프를 출력한다'
      When call cmd_graph "v4.3.0" "uri1.0"
      The status should be success
      The output should include "base"
      The output should include "└─ custom_emoji"
      The output should include "theme"
    End

    It '--format dot으로 DOT 형식을 출력한다'
      When call cmd_graph "v4.3.0" "uri1.0" "--format" "dot"
      The status should be success
      The output should include "digraph dependencies"
      The output should include '"base" -> "custom_emoji";'
    End

    It '--format=dot 형식을 지원한다'
      When call cmd_graph "v4.3.0" "uri1.0" "--format=dot"
      The status should be success
      The output should include "digraph dependencies"
    End

    It '--include-dev로 개발 의존성을 포함한다'
      _manifest="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      yq eval -i '.features.dev_base = {"name": "개발 기반", "description": "개발용", "dependencies": []}' "$_manifest"
      yq eval -i '.features.custom_emoji."dev-dependencies" = ["dev_base"]' "$_manifest"

      When call cmd_graph "v4.3.0" "uri1.0" "--include-dev"
      The status should be success
      The output should include "dev_base"
      The output should include "custom_emoji"
    End

    It '상속된 feature를 포함한다'
      create_test_inherited_patchset "$TEST_TMPDIR"
      When call cmd_graph "v4.3.0" "uri1.1"
      The status should be success
      The output should include "base"
      The output should include "extra"
    End

    It '지원하지 않는 format이면 실패한다'
      When run script -e -c "
        URI_ROOT='$TEST_TMPDIR'; export URI_ROOT
        . '$LIB_DIR/common.sh'; . '$LIB_DIR/yaml.sh'; . '$LIB_DIR/git.sh'
        . '$LIB_DIR/topsort.sh'; . '$LIB_DIR/inherit.sh'; . '$LIB_DIR/state.sh'
        . '$LIB_DIR/commands/graph.sh'
        cmd_graph v4.3.0 uri1.0 --format json
      "
      The status should be failure
      The stderr should include '지원하지 않는 출력 형식'
    End
  End

  Describe 'graph_usage()'
    It '도움말을 출력한다'
      When call graph_usage
      The output should include "사용법"
      The output should include "uri graph"
      The output should include "--format"
    End
  End
End
