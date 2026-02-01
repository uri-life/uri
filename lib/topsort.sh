#!/bin/sh
# topsort.sh - 위상 정렬 유틸리티
# POSIX 호환 셸 스크립트
# 의존성: tsort (POSIX 표준 유틸리티)

# tsort를 사용한 위상 정렬
# 입력: 간선 쌍이 담긴 파일 (각 줄: "의존하는_노드 의존되는_노드")
# 출력: 정렬된 노드 목록 (역순, 즉 의존성이 먼저 나옴)
# 사용법: topsort_file "/path/to/edges.txt"
topsort_file() {
    _edges_file="$1"

    # tsort 실행 및 순환 감지
    _result=$(tsort "$_edges_file" 2>&1)
    _exit_code=$?

    if [ $_exit_code -ne 0 ]; then
        # tsort가 순환을 감지하면 에러 메시지 출력
        if echo "$_result" | grep -q "cycle"; then
            die "순환 의존성이 발견되었습니다: $_result"
        else
            die "위상 정렬 실패: $_result"
        fi
    fi

    echo "$_result"
}

# manifest에서 feature 의존성 그래프 생성
# 입력: manifest.yaml 경로, 임시 파일 경로 (간선 저장용)
# 출력: 간선 파일에 의존성 기록
# 사용법: build_dependency_graph "manifest.yaml" "/tmp/edges.txt"
build_dependency_graph() {
    _manifest="$1"
    _edges_file="$2"

    # 간선 파일 초기화
    : > "$_edges_file"

    # 모든 feature 목록
    _features=$(yaml_list_features "$_manifest")

    # 각 feature의 의존성을 간선으로 변환
    for _feature in $_features; do
        # feature 자체를 노드로 추가 (의존성 없어도 포함되도록)
        echo "$_feature $_feature" >> "$_edges_file"

        # 의존성 목록 가져오기
        _deps=$(yaml_get_feature_dependencies "$_manifest" "$_feature" 2>/dev/null)

        for _dep in $_deps; do
            # 빈 문자열이나 null 무시
            if [ -n "$_dep" ] && [ "$_dep" != "null" ]; then
                # "feature depends_on dependency" 형식
                # tsort는 역순으로 출력하므로 간선 방향 주의
                echo "$_feature $_dep" >> "$_edges_file"
            fi
        done
    done
}

# manifest에서 정렬된 feature 목록 반환
# 사용법: get_sorted_features "manifest.yaml"
# 출력: 의존성 순서로 정렬된 feature 목록 (의존되는 것이 먼저)
get_sorted_features() {
    _manifest="$1"

    # 임시 파일 생성
    _edges_file=$(make_temp)

    # 의존성 그래프 생성
    build_dependency_graph "$_manifest" "$_edges_file"

    # 파일이 비어있으면 빈 목록 반환
    if [ ! -s "$_edges_file" ]; then
        return 0
    fi

    # 위상 정렬 실행 후 역순으로 변환 (tsort는 의존하는 것이 먼저 나오므로)
    topsort_file "$_edges_file" | reverse_lines
}

# 특정 feature와 그 의존성들만 정렬하여 반환
# 사용법: get_feature_with_deps "manifest.yaml" "feature_name"
# 출력: feature와 그 의존성들을 의존성 순서로 정렬
get_feature_with_deps() {
    _manifest="$1"
    _target="$2"

    # 임시 파일들
    _edges_file=$(make_temp)
    _required_file=$(make_temp)

    # 모든 의존성 그래프 생성
    build_dependency_graph "$_manifest" "$_edges_file"

    # 타겟 feature부터 시작하여 재귀적으로 필요한 feature 수집
    _collect_deps "$_manifest" "$_target" "$_required_file"

    # 필요한 feature들만 포함하는 간선 파일 생성
    _filtered_edges=$(make_temp)
    while IFS= read -r _line; do
        _from=$(echo "$_line" | cut -d' ' -f1)
        _to=$(echo "$_line" | cut -d' ' -f2)

        # 두 노드 모두 필요한 목록에 있는 경우만 포함
        if grep -q "^${_from}$" "$_required_file" && grep -q "^${_to}$" "$_required_file"; then
            echo "$_line"
        fi
    done < "$_edges_file" > "$_filtered_edges"

    # 정렬 실행 후 역순으로 변환 (의존되는 것이 먼저 오도록)
    if [ -s "$_filtered_edges" ]; then
        topsort_file "$_filtered_edges" | reverse_lines
    fi
}

# 재귀적으로 의존성 수집 (내부 함수)
_collect_deps() {
    _manifest="$1"
    _feature="$2"
    _output_file="$3"

    # 이미 수집된 경우 스킵
    if grep -q "^${_feature}$" "$_output_file" 2>/dev/null; then
        return
    fi

    # 현재 feature 추가
    echo "$_feature" >> "$_output_file"

    # 의존성 수집
    _deps=$(yaml_get_feature_dependencies "$_manifest" "$_feature" 2>/dev/null)
    for _dep in $_deps; do
        if [ -n "$_dep" ] && [ "$_dep" != "null" ]; then
            _collect_deps "$_manifest" "$_dep" "$_output_file"
        fi
    done
}

# 정렬 결과를 역순으로 변환 (collapse 등에서 사용)
# 사용법: echo "$sorted_list" | reverse_lines
reverse_lines() {
    # POSIX 호환 방식으로 역순 정렬
    # tail -r은 BSD 전용이므로 awk 사용
    awk '{a[NR]=$0} END {for(i=NR;i>=1;i--) print a[i]}'
}

# 순환 의존성 검사만 수행
# 사용법: check_circular_deps "manifest.yaml"
check_circular_deps() {
    _manifest="$1"
    _edges_file=$(make_temp)

    build_dependency_graph "$_manifest" "$_edges_file"

    if [ ! -s "$_edges_file" ]; then
        return 0
    fi

    # tsort 실행하여 순환 검사
    if ! tsort "$_edges_file" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
