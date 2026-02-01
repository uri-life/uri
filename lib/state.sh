#!/bin/sh
# state.sh - 작업 상태 관리 유틸리티
# POSIX 호환 셸 스크립트
# expand/collapse 중 충돌 발생 시 상태 저장 및 복원

# 상태 파일 경로 (대상 리포지토리 내에 저장)
STATE_FILE=".uri_state"

# 상태 파일 전체 경로 반환
# 사용법: state_file "/path/to/repo"
state_file() {
    _repo="$1"
    echo "${_repo}/${STATE_FILE}"
}

# 상태 저장
# 사용법: state_save "/path/to/repo" "key" "value"
state_save() {
    _repo="$1"
    _key="$2"
    _value="$3"
    _state_file=$(state_file "$_repo")

    # 파일이 없으면 생성
    if [ ! -f "$_state_file" ]; then
        : > "$_state_file"
    fi

    # 기존 키가 있으면 제거
    if grep -q "^${_key}=" "$_state_file" 2>/dev/null; then
        _tmp=$(make_temp)
        grep -v "^${_key}=" "$_state_file" > "$_tmp"
        mv "$_tmp" "$_state_file"
    fi

    # 새 값 추가
    echo "${_key}=${_value}" >> "$_state_file"
}

# 상태 읽기
# 사용법: state_get "/path/to/repo" "key"
state_get() {
    _repo="$1"
    _key="$2"
    _state_file=$(state_file "$_repo")

    if [ -f "$_state_file" ]; then
        grep "^${_key}=" "$_state_file" 2>/dev/null | cut -d'=' -f2-
    fi
}

# 특정 상태 키 삭제
# 사용법: state_delete "/path/to/repo" "key"
state_delete() {
    _repo="$1"
    _key="$2"
    _state_file=$(state_file "$_repo")

    if [ -f "$_state_file" ]; then
        _tmp=$(make_temp)
        grep -v "^${_key}=" "$_state_file" > "$_tmp"
        mv "$_tmp" "$_state_file"
    fi
}

# 상태 파일 전체 삭제
# 사용법: state_clear "/path/to/repo"
state_clear() {
    _repo="$1"
    _state_file=$(state_file "$_repo")
    rm -f "$_state_file"
}

# 상태 파일 존재 확인
# 사용법: if state_exists "/path/to/repo"; then ...
state_exists() {
    _repo="$1"
    _state_file=$(state_file "$_repo")
    [ -f "$_state_file" ]
}

# 진행 중인 작업 확인
# 사용법: if state_in_progress "/path/to/repo"; then ...
state_in_progress() {
    _repo="$1"
    _operation=$(state_get "$_repo" "operation")
    [ -n "$_operation" ]
}

# expand 상태 저장
# 사용법: state_save_expand "/path/to/repo" "v4.3.2" "uri1.23" "feature1 feature2 feature3" "1"
state_save_expand() {
    _repo="$1"
    _mastodon_ver="$2"
    _uri_ver="$3"
    _features="$4"      # 공백 구분 feature 목록
    _current_index="$5" # 현재 처리 중인 feature 인덱스 (0부터)

    state_save "$_repo" "operation" "expand"
    state_save "$_repo" "mastodon_version" "$_mastodon_ver"
    state_save "$_repo" "uri_version" "$_uri_ver"
    state_save "$_repo" "features" "$_features"
    state_save "$_repo" "current_index" "$_current_index"
    state_save "$_repo" "start_commit" "$(git_current_commit "$_repo")"
}

# collapse 상태 저장
# 사용법: state_save_collapse "/path/to/repo" "v4.3.2" "uri1.23" "feature1 feature2" "1"
state_save_collapse() {
    _repo="$1"
    _mastodon_ver="$2"
    _uri_ver="$3"
    _features="$4"
    _current_index="$5"

    state_save "$_repo" "operation" "collapse"
    state_save "$_repo" "mastodon_version" "$_mastodon_ver"
    state_save "$_repo" "uri_version" "$_uri_ver"
    state_save "$_repo" "features" "$_features"
    state_save "$_repo" "current_index" "$_current_index"
}

# 현재 작업 상태 출력 (사용자 안내용)
# 사용법: state_show "/path/to/repo"
state_show() {
    _repo="$1"
    _state_file=$(state_file "$_repo")

    if [ ! -f "$_state_file" ]; then
        info "진행 중인 작업이 없습니다."
        return 1
    fi

    _operation=$(state_get "$_repo" "operation")
    _mastodon_ver=$(state_get "$_repo" "mastodon_version")
    _uri_ver=$(state_get "$_repo" "uri_version")
    _features=$(state_get "$_repo" "features")
    _current_index=$(state_get "$_repo" "current_index")

    # 현재 feature 계산
    _count=0
    _current_feature=""
    for _f in $_features; do
        if [ "$_count" -eq "$_current_index" ]; then
            _current_feature="$_f"
            break
        fi
        _count=$((_count + 1))
    done

    echo "진행 중인 작업:"
    echo "  작업: $_operation"
    echo "  Mastodon 버전: $_mastodon_ver"
    echo "  URI 버전: $_uri_ver"
    echo "  현재 feature: $_current_feature ($((_current_index + 1))/$(echo $_features | wc -w | tr -d ' '))"
    echo ""
    echo "충돌을 해결한 후:"
    echo "  계속하려면: uri $_operation --continue"
    echo "  중단하려면: uri $_operation --abort"
}

# 처리된 feature 목록 반환 (현재 인덱스 전까지)
# 사용법: state_get_completed_features "/path/to/repo"
state_get_completed_features() {
    _repo="$1"
    _features=$(state_get "$_repo" "features")
    _current_index=$(state_get "$_repo" "current_index")

    _count=0
    _completed=""
    for _f in $_features; do
        if [ "$_count" -lt "$_current_index" ]; then
            _completed="$_completed $_f"
        fi
        _count=$((_count + 1))
    done

    echo "$_completed" | sed 's/^ *//'
}

# 남은 feature 목록 반환 (현재 인덱스부터)
# 사용법: state_get_remaining_features "/path/to/repo"
state_get_remaining_features() {
    _repo="$1"
    _features=$(state_get "$_repo" "features")
    _current_index=$(state_get "$_repo" "current_index")

    _count=0
    _remaining=""
    for _f in $_features; do
        if [ "$_count" -ge "$_current_index" ]; then
            _remaining="$_remaining $_f"
        fi
        _count=$((_count + 1))
    done

    echo "$_remaining" | sed 's/^ *//'
}

# 현재 인덱스 증가
# 사용법: state_increment_index "/path/to/repo"
state_increment_index() {
    _repo="$1"
    _current=$(state_get "$_repo" "current_index")
    _new=$((_current + 1))
    state_save "$_repo" "current_index" "$_new"
}
