#!/bin/sh
# yaml.sh - YAML 파싱 유틸리티 (yq 래퍼)
# POSIX 호환 셸 스크립트
# 의존성: yq (mikefarah/yq v4+)

# YAML 값 읽기
# 사용법: yaml_get "file.yaml" ".path.to.value"
yaml_get() {
    _file="$1"
    _path="$2"
    yq eval "$_path" "$_file"
}

# YAML 값 쓰기
# 사용법: yaml_set "file.yaml" ".path.to.value" "new_value"
yaml_set() {
    _file="$1"
    _path="$2"
    _value="$3"
    yq eval -i "$_path = \"$_value\"" "$_file"
}

# YAML 값 쓰기 (raw - 따옴표 없이 그대로)
# 사용법: yaml_set_raw "file.yaml" ".path.to.value" "[]"
yaml_set_raw() {
    _file="$1"
    _path="$2"
    _value="$3"
    yq eval -i "$_path = $_value" "$_file"
}

# YAML 배열에 값 추가
# 사용법: yaml_append "file.yaml" ".path.to.array" "new_item"
yaml_append() {
    _file="$1"
    _path="$2"
    _value="$3"
    yq eval -i "$_path += [\"$_value\"]" "$_file"
}

# YAML 경로 삭제
# 사용법: yaml_delete "file.yaml" ".path.to.delete"
yaml_delete() {
    _file="$1"
    _path="$2"
    yq eval -i "del($_path)" "$_file"
}

# YAML 객체의 키 목록 반환 (줄바꿈 구분)
# 사용법: yaml_keys "file.yaml" ".path.to.object"
yaml_keys() {
    _file="$1"
    _path="${2:-.}"
    yq eval "$_path | keys | .[]" "$_file"
}

# YAML 경로 존재 여부 확인
# 사용법: if yaml_has "file.yaml" ".path.to.check"; then ...
yaml_has() {
    _file="$1"
    _path="$2"
    _result=$(yq eval "$_path | . != null" "$_file")
    [ "$_result" = "true" ]
}

# YAML 배열 길이 반환
# 사용법: yaml_array_len "file.yaml" ".path.to.array"
yaml_array_len() {
    _file="$1"
    _path="$2"
    yq eval "$_path | length" "$_file"
}

# YAML 배열을 줄바꿈 구분 문자열로 반환
# 사용법: yaml_array_items "file.yaml" ".path.to.array"
yaml_array_items() {
    _file="$1"
    _path="$2"
    yq eval "$_path | .[]" "$_file"
}

# 두 YAML 파일 병합 (overlay가 base를 덮어씀)
# 사용법: yaml_merge "base.yaml" "overlay.yaml" > "merged.yaml"
yaml_merge() {
    _base="$1"
    _overlay="$2"
    yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$_base" "$_overlay"
}

# 새 YAML 파일 생성
# 사용법: yaml_create "file.yaml" "key" "value"
yaml_create() {
    _file="$1"
    _key="$2"
    _value="$3"
    echo "$_key: $_value" > "$_file"
}

# 빈 YAML 파일 생성
# 사용법: yaml_create_empty "file.yaml"
yaml_create_empty() {
    _file="$1"
    echo "---" > "$_file"
}

# feature 정보 읽기 헬퍼
# 사용법: yaml_get_feature_name "manifest.yaml" "feature_key"
yaml_get_feature_name() {
    _file="$1"
    _feature="$2"
    yaml_get "$_file" ".features.$_feature.name"
}

yaml_get_feature_description() {
    _file="$1"
    _feature="$2"
    yaml_get "$_file" ".features.$_feature.description"
}

yaml_get_feature_dependencies() {
    _file="$1"
    _feature="$2"
    yaml_array_items "$_file" ".features.$_feature.dependencies"
}

yaml_get_feature_dev_dependencies() {
    _file="$1"
    _feature="$2"
    _path=".features.$_feature.\"dev-dependencies\""

    if yaml_has "$_file" "$_path"; then
        yaml_array_items "$_file" "$_path"
    fi
}

# feature 목록 반환
# 사용법: yaml_list_features "manifest.yaml"
yaml_list_features() {
    _file="$1"
    if yaml_has "$_file" ".features"; then
        yaml_keys "$_file" ".features"
    fi
}

# inherits 값 읽기
# 사용법: yaml_get_inherits "manifest.yaml"
yaml_get_inherits() {
    _file="$1"
    _val=$(yaml_get "$_file" ".inherits")
    if [ "$_val" = "null" ]; then
        echo ""
    else
        echo "$_val"
    fi
}

# excludes 배열이 명시되어 있는지 확인
# 사용법: if yaml_has_excludes "manifest.yaml"; then ...
yaml_has_excludes() {
    _yhe_file="$1"
    _yhe_result=$(yq eval 'has("excludes")' "$_yhe_file")
    [ "$_yhe_result" = "true" ]
}

# excludes 스키마 검증
# 누락은 빈 배열로 허용하고, 명시된 값은 중복 없는 비어 있지 않은 문자열 배열이어야 합니다.
yaml_validate_excludes() {
    _yve_file="$1"

    if ! yaml_has_excludes "$_yve_file"; then
        return 0
    fi

    _yve_tag=$(yq eval '.excludes | tag' "$_yve_file")
    if [ "$_yve_tag" != "!!seq" ]; then
        die "excludes는 문자열 배열이어야 합니다: feature <excludes> ($_yve_file)"
    fi

    _yve_invalid_count=$(yq eval '[.excludes[] | select(tag != "!!str" or test("^[[:space:]]*$"))] | length' "$_yve_file")
    if [ "$_yve_invalid_count" -ne 0 ]; then
        _yve_invalid=$(yq eval '[.excludes[] | select(tag != "!!str" or test("^[[:space:]]*$"))] | .[0] | to_json' "$_yve_file")
        die "excludes에는 비어 있지 않은 문자열만 사용할 수 있습니다: feature $_yve_invalid ($_yve_file)"
    fi

    _yve_unique=$(yq eval '(.excludes | length) == (.excludes | unique | length)' "$_yve_file")
    if [ "$_yve_unique" != "true" ]; then
        _yve_duplicate=$(yq eval '.excludes | group_by(.) | map(select(length > 1) | .[0]) | .[0] // ""' "$_yve_file")
        die "excludes에 중복된 feature가 있습니다: $_yve_duplicate ($_yve_file)"
    fi
}

# excludes 목록 반환
# 사용법: yaml_list_excludes "manifest.yaml"
yaml_list_excludes() {
    _yle_file="$1"
    if yaml_has_excludes "$_yle_file"; then
        yq eval '.excludes[]' "$_yle_file"
    fi
}

# excludes에 feature가 있는지 확인
# 사용법: if yaml_excludes_feature "manifest.yaml" "feature"; then ...
yaml_excludes_feature() {
    _yef_file="$1"
    _yef_feature="$2"
    _yef_result=$(URI_YAML_VALUE="$_yef_feature" yq eval '(.excludes // []) | any_c(. == strenv(URI_YAML_VALUE))' "$_yef_file")
    [ "$_yef_result" = "true" ]
}

# excludes에 feature 추가
yaml_append_exclude() {
    _yae_file="$1"
    _yae_feature="$2"
    URI_YAML_VALUE="$_yae_feature" yq eval -i '.excludes = ((.excludes // []) + [strenv(URI_YAML_VALUE)])' "$_yae_file"
}

# excludes에서 feature 제거
yaml_remove_exclude() {
    _yre_file="$1"
    _yre_feature="$2"
    URI_YAML_VALUE="$_yre_feature" yq eval -i '.excludes = [.excludes[] | select(. != strenv(URI_YAML_VALUE))]' "$_yre_file"
}

# feature 전체 객체를 JSON으로 반환 (디버깅/처리용)
# 사용법: yaml_get_features_json "manifest.yaml"
yaml_get_features_json() {
    _file="$1"
    yq eval '.features' -o=json "$_file"
}
