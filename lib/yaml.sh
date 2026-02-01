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

# feature 전체 객체를 JSON으로 반환 (디버깅/처리용)
# 사용법: yaml_get_features_json "manifest.yaml"
yaml_get_features_json() {
    _file="$1"
    yq eval '.features' -o=json "$_file"
}
