#!/bin/sh
# inherit.sh - 상속 처리 유틸리티
# POSIX 호환 셸 스크립트

# uri 버전 문자열 파싱
# 입력: "v4.3.2+uri1.23" 또는 "uri1.23"
# 출력: mastodon_ver uri_ver (공백 구분)
# 사용법: parse_uri_version "v4.3.2+uri1.23"
parse_uri_version() {
    _version_str="$1"

    case "$_version_str" in
        *+*)
            # v4.3.2+uri1.23 형식
            _mastodon_ver=$(echo "$_version_str" | cut -d'+' -f1)
            _uri_ver=$(echo "$_version_str" | cut -d'+' -f2)
            echo "$_mastodon_ver $_uri_ver"
            ;;
        *)
            # uri1.23 형식 (mastodon 버전은 컨텍스트에서 결정)
            echo " $_version_str"
            ;;
    esac
}

# manifest 경로 계산
# 사용법: resolve_manifest_path "v4.3.2" "uri1.23"
resolve_manifest_path() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    echo "${URI_ROOT}/versions/${_mastodon_ver}/patches/${_uri_ver}/manifest.yaml"
}

# 패치 디렉터리 경로 계산
# 사용법: resolve_patch_dir "v4.3.2" "uri1.23"
resolve_patch_dir() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    echo "${URI_ROOT}/versions/${_mastodon_ver}/patches/${_uri_ver}"
}

# 패치 파일 경로 계산
# 사용법: resolve_patch_path "v4.3.2" "uri1.23" "custom_emoji"
resolve_patch_path() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _feature="$3"
    echo "${URI_ROOT}/versions/${_mastodon_ver}/patches/${_uri_ver}/${_feature}.patch"
}

# 상속 체인을 따라가며 모든 manifest 경로 수집
# 사용법: get_inheritance_chain "v4.3.2" "uri1.23"
# 출력: manifest 경로들 (줄바꿈 구분, 자식부터 조상 순)
get_inheritance_chain() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _visited=$(make_temp)

    _get_chain_recursive "$_mastodon_ver" "$_uri_ver" "$_visited"
}

# 재귀적으로 상속 체인 탐색 (내부 함수)
_get_chain_recursive() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _visited="$3"

    _manifest=$(resolve_manifest_path "$_mastodon_ver" "$_uri_ver")

    # 파일 존재 확인
    if [ ! -f "$_manifest" ]; then
        die "manifest를 찾을 수 없습니다: $_manifest"
    fi

    # 순환 상속 감지
    if grep -q "^${_manifest}$" "$_visited" 2>/dev/null; then
        die "순환 상속이 감지되었습니다: $_manifest"
    fi

    # 방문 기록
    echo "$_manifest" >> "$_visited"

    # 현재 manifest 출력
    echo "$_manifest"

    # 상속 확인
    _inherits=$(yaml_get_inherits "$_manifest")

    if [ -n "$_inherits" ]; then
        # 상속 버전 파싱
        _parsed=$(parse_uri_version "$_inherits")
        _parent_mastodon=$(echo "$_parsed" | cut -d' ' -f1)
        _parent_uri=$(echo "$_parsed" | cut -d' ' -f2)

        # mastodon 버전이 비어있으면 현재와 동일
        if [ -z "$_parent_mastodon" ]; then
            _parent_mastodon="$_mastodon_ver"
        fi

        # 재귀적으로 부모 탐색
        _get_chain_recursive "$_parent_mastodon" "$_parent_uri" "$_visited"
    fi
}

# 상속을 해석하여 병합된 features 반환 (임시 manifest 파일 경로)
# 사용법: resolve_inheritance "v4.3.2" "uri1.23"
# 출력: 병합된 features가 포함된 임시 manifest 경로
resolve_inheritance() {
    _mastodon_ver="$1"
    _uri_ver="$2"

    # 상속 체인 가져오기 (자식 → 조상 순서)
    _chain=$(get_inheritance_chain "$_mastodon_ver" "$_uri_ver")

    # 역순으로 변환 (조상 → 자식 순서로 병합해야 자식이 덮어씀)
    _reversed=$(echo "$_chain" | reverse_lines)

    # 병합된 결과를 저장할 임시 파일
    _merged=$(make_temp)
    yaml_create_empty "$_merged"

    # 순서대로 병합 (나중 것이 덮어씀)
    for _manifest in $_reversed; do
        # features 부분만 추출하여 병합
        if yaml_has "$_manifest" ".features"; then
            # 현재 manifest의 features를 병합
            yq eval-all 'select(fileIndex == 0).features * select(fileIndex == 1).features | {"features": .}' \
                "$_merged" "$_manifest" > "${_merged}.tmp"
            mv "${_merged}.tmp" "$_merged"
        fi
    done

    echo "$_merged"
}

# 병합된 feature 목록 반환
# 사용법: get_all_features "v4.3.2" "uri1.23"
get_all_features() {
    _mastodon_ver="$1"
    _uri_ver="$2"

    _merged=$(resolve_inheritance "$_mastodon_ver" "$_uri_ver")
    yaml_list_features "$_merged"
}

# 특정 feature가 존재하는지 확인 (상속 포함)
# 사용법: if has_feature "v4.3.2" "uri1.23" "custom_emoji"; then ...
has_feature() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _feature="$3"

    _merged=$(resolve_inheritance "$_mastodon_ver" "$_uri_ver")
    yaml_has "$_merged" ".features.$_feature"
}

# 특정 feature의 패치 파일 경로 찾기 (상속 체인에서)
# 사용법: find_patch_file "v4.3.2" "uri1.23" "custom_emoji"
find_patch_file() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _feature="$3"

    # 상속 체인을 따라가며 패치 파일 찾기 (자식 우선)
    _chain=$(get_inheritance_chain "$_mastodon_ver" "$_uri_ver")

    for _manifest in $_chain; do
        _patch_dir=$(dirname "$_manifest")
        _patch_file="${_patch_dir}/${_feature}.patch"

        if [ -f "$_patch_file" ]; then
            echo "$_patch_file"
            return 0
        fi
    done

    return 1
}
