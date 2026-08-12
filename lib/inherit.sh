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
    resolve_inheritance_with_manifest "$1" "$2" ""
}

# 현재 manifest 대신 후보 파일을 사용하여 상속을 해석합니다.
# exclude/include가 원본을 바꾸기 전에 결과를 검증할 때 사용합니다.
resolve_inheritance_with_manifest() {
    _ri_mastodon_ver="$1"
    _ri_uri_ver="$2"
    _ri_override="${3:-}"
    _ri_target_manifest=$(resolve_manifest_path "$_ri_mastodon_ver" "$_ri_uri_ver")

    # 상속 체인 가져오기 (자식 → 조상 순서)
    _ri_chain=$(get_inheritance_chain "$_ri_mastodon_ver" "$_ri_uri_ver")

    # 역순으로 변환 (조상 → 자식 순서로 병합해야 자식이 덮어씀)
    _ri_reversed=$(echo "$_ri_chain" | reverse_lines)

    # 병합된 결과를 저장할 임시 파일
    _ri_merged=$(make_temp)
    echo "features: {}" > "$_ri_merged"

    for _ri_manifest in $_ri_reversed; do
        _ri_effective_manifest="$_ri_manifest"
        if [ -n "$_ri_override" ] && [ "$_ri_manifest" = "$_ri_target_manifest" ]; then
            _ri_effective_manifest="$_ri_override"
        fi

        yaml_validate_excludes "$_ri_effective_manifest"
        _ri_excludes=$(yaml_list_excludes "$_ri_effective_manifest")

        # excludes는 이 단계에서 상속받은 feature만 지정할 수 있습니다.
        for _ri_excluded in $_ri_excludes; do
            if yaml_has "$_ri_effective_manifest" ".features.$_ri_excluded"; then
                die "같은 manifest에서 feature를 선언하고 제외할 수 없습니다: $_ri_excluded ($_ri_manifest)"
            fi
            if ! yaml_has "$_ri_merged" ".features.$_ri_excluded"; then
                die "상속된 feature를 찾을 수 없습니다: $_ri_excluded ($_ri_manifest)"
            fi
        done

        # 현재 features를 병합한 뒤 이 단계의 excludes를 적용합니다.
        if yaml_has "$_ri_effective_manifest" ".features"; then
            yq eval-all '(select(fileIndex == 0).features // {}) * (select(fileIndex == 1).features // {}) | {"features": .}' \
                "$_ri_merged" "$_ri_effective_manifest" > "${_ri_merged}.tmp"
            mv "${_ri_merged}.tmp" "$_ri_merged"
        fi

        for _ri_excluded in $_ri_excludes; do
            yaml_delete "$_ri_merged" ".features.$_ri_excluded"
        done
    done

    _validate_resolved_dependencies "$_ri_merged" "$_ri_target_manifest"
    echo "$_ri_merged"
}

# 최종 활성 feature의 일반/개발 의존성이 모두 존재하는지 검증합니다.
_validate_resolved_dependencies() {
    _vrd_manifest="$1"
    _vrd_source_manifest="$2"
    _vrd_missing=$(make_temp)
    : > "$_vrd_missing"

    _vrd_features=$(yaml_list_features "$_vrd_manifest")
    for _vrd_feature in $_vrd_features; do
        _vrd_dependencies=$(yaml_get_feature_dependencies "$_vrd_manifest" "$_vrd_feature" 2>/dev/null)
        for _vrd_dependency in $_vrd_dependencies; do
            if [ -n "$_vrd_dependency" ] && [ "$_vrd_dependency" != "null" ] && \
                ! yaml_has "$_vrd_manifest" ".features.$_vrd_dependency"; then
                printf '%s|dependencies|%s\n' "$_vrd_feature" "$_vrd_dependency" >> "$_vrd_missing"
            fi
        done

        _vrd_dev_dependencies=$(yaml_get_feature_dev_dependencies "$_vrd_manifest" "$_vrd_feature" 2>/dev/null)
        for _vrd_dependency in $_vrd_dev_dependencies; do
            if [ -n "$_vrd_dependency" ] && [ "$_vrd_dependency" != "null" ] && \
                ! yaml_has "$_vrd_manifest" ".features.$_vrd_dependency"; then
                printf '%s|dev-dependencies|%s\n' "$_vrd_feature" "$_vrd_dependency" >> "$_vrd_missing"
            fi
        done
    done

    if [ -s "$_vrd_missing" ]; then
        warn "누락된 feature 의존성이 있습니다: $_vrd_source_manifest"
        while IFS='|' read -r _vrd_feature _vrd_kind _vrd_dependency; do
            printf '  - %s.%s -> %s\n' "$_vrd_feature" "$_vrd_kind" "$_vrd_dependency" >&2
        done < "$_vrd_missing"
        die "manifest 의존성을 해석할 수 없습니다."
    fi
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

# 이름으로 패치 파일 경로 찾기 (상속 체인에서)
# 사용법: find_named_patch_file "v4.3.2" "uri1.23" "custom_emoji~ANTE"
find_named_patch_file() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _patch_name="$3"

    _chain=$(get_inheritance_chain "$_mastodon_ver" "$_uri_ver")

    for _manifest in $_chain; do
        _patch_dir=$(dirname "$_manifest")
        _patch_file="${_patch_dir}/${_patch_name}.patch"

        if [ -f "$_patch_file" ]; then
            echo "$_patch_file"
            return 0
        fi
    done

    return 1
}

# apply 전처리 패치 찾기
# 사용법: find_ante_patch "v4.3.2" "uri1.23" "feature"
find_ante_patch() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _feature="$3"

    find_named_patch_file "$_mastodon_ver" "$_uri_ver" "${_feature}~ANTE"
}

# apply 후처리 패치 찾기
# 사용법: find_post_patch "v4.3.2" "uri1.23" "feature"
find_post_patch() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _feature="$3"

    find_named_patch_file "$_mastodon_ver" "$_uri_ver" "${_feature}~POST"
}

# 충돌 해소용 pair 패치 찾기
# 사용법: find_pair_resolution_patch "v4.3.2" "uri1.23" "current" "completed"
find_pair_resolution_patch() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _current="$3"
    _completed="$4"

    find_named_patch_file "$_mastodon_ver" "$_uri_ver" "${_current}~${_completed}"
}

# 정렬된 feature 목록과 현재 인덱스로 적용 가능한 pair 패치 찾기
# 사용법: find_applicable_pair_resolution_patch "v4.3.2" "uri1.23" "current" "a b c" "2"
find_applicable_pair_resolution_patch() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _current="$3"
    _features_str="$4"
    _current_index="$5"

    _count=0
    _completed=""
    for _feature in $_features_str; do
        if [ "$_count" -lt "$_current_index" ]; then
            _completed="${_completed}
${_feature}"
        fi
        _count=$((_count + 1))
    done

    for _completed_feature in $(printf '%s\n' "$_completed" | sed '/^$/d' | reverse_lines); do
        _patch=$(find_pair_resolution_patch "$_mastodon_ver" "$_uri_ver" "$_current" "$_completed_feature" || true)
        if [ -n "$_patch" ]; then
            echo "$_patch"
            return 0
        fi
    done

    return 1
}
