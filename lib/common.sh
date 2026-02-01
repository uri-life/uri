#!/bin/sh
# common.sh - 공통 유틸리티 함수
# POSIX 호환 셸 스크립트

# 색상 코드 (tty일 때만 사용)
if [ -t 1 ]; then
    COLOR_RED='\033[0;31m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_GREEN='\033[0;32m'
    COLOR_BLUE='\033[0;34m'
    COLOR_RESET='\033[0m'
else
    COLOR_RED=''
    COLOR_YELLOW=''
    COLOR_GREEN=''
    COLOR_BLUE=''
    COLOR_RESET=''
fi

# 에러 메시지 출력 후 종료
# 사용법: die "에러 메시지"
die() {
    printf "${COLOR_RED}error:${COLOR_RESET} %s\n" "$1" >&2
    exit 1
}

# 경고 메시지 출력
# 사용법: warn "경고 메시지"
warn() {
    printf "${COLOR_YELLOW}warning:${COLOR_RESET} %s\n" "$1" >&2
}

# 정보 메시지 출력
# 사용법: info "정보 메시지"
info() {
    printf "${COLOR_BLUE}info:${COLOR_RESET} %s\n" "$1"
}

# 성공 메시지 출력
# 사용법: success "성공 메시지"
success() {
    printf "${COLOR_GREEN}success:${COLOR_RESET} %s\n" "$1"
}

# 명령어 존재 확인
# 사용법: require_cmd "yq" "yq가 필요합니다. brew install yq"
require_cmd() {
    _cmd="$1"
    _msg="${2:-$_cmd 명령어가 필요합니다.}"
    if ! command -v "$_cmd" >/dev/null 2>&1; then
        die "$_msg"
    fi
}

# 상대 경로를 절대 경로로 변환
# 사용법: resolve_path "./relative/path"
resolve_path() {
    _path="$1"
    if [ -d "$_path" ]; then
        # 디렉터리인 경우
        (cd "$_path" && pwd)
    elif [ -f "$_path" ]; then
        # 파일인 경우
        _dir=$(dirname "$_path")
        _base=$(basename "$_path")
        echo "$(cd "$_dir" && pwd)/$_base"
    else
        # 존재하지 않는 경로 - 부모 디렉터리 기준으로 해석
        _dir=$(dirname "$_path")
        _base=$(basename "$_path")
        if [ -d "$_dir" ]; then
            echo "$(cd "$_dir" && pwd)/$_base"
        else
            # 부모도 없으면 현재 디렉터리 기준
            echo "$(pwd)/$_path"
        fi
    fi
}

# URI_ROOT 계산 (manifest.yaml이 있는 디렉터리)
# 현재 디렉터리부터 상위로 올라가며 manifest.yaml 탐색
find_uri_root() {
    _dir="$PWD"
    while [ "$_dir" != "/" ]; do
        if [ -f "$_dir/manifest.yaml" ]; then
            echo "$_dir"
            return 0
        fi
        _dir=$(dirname "$_dir")
    done
    return 1
}

# URI_ROOT 설정 (필수)
# 사용법: require_uri_root
require_uri_root() {
    URI_ROOT=$(find_uri_root) || die "manifest.yaml을 찾을 수 없습니다. 'uri init'을 먼저 실행하세요."
    export URI_ROOT
}

# URI_ROOT 설정 (선택적 - init 명령 등에서 사용)
# 사용법: set_uri_root_if_exists
set_uri_root_if_exists() {
    if URI_ROOT=$(find_uri_root 2>/dev/null); then
        export URI_ROOT
        return 0
    fi
    return 1
}

# 버전 디렉터리 경로 반환
# 사용법: version_dir "v4.3.2"
version_dir() {
    echo "${URI_ROOT}/versions/$1"
}

# uri 버전 디렉터리 경로 반환
# 사용법: uri_version_dir "v4.3.2" "uri1.23"
uri_version_dir() {
    echo "${URI_ROOT}/versions/$1/patches/$2"
}

# 파일/디렉터리 존재 확인
# 사용법: require_file "path/to/file" "파일을 찾을 수 없습니다"
require_file() {
    if [ ! -f "$1" ]; then
        die "${2:-파일을 찾을 수 없습니다: $1}"
    fi
}

require_dir() {
    if [ ! -d "$1" ]; then
        die "${2:-디렉터리를 찾을 수 없습니다: $1}"
    fi
}

# 임시 파일 생성 및 정리
# trap과 함께 사용
_TEMP_FILES=""

make_temp() {
    _tmp=$(mktemp)
    _TEMP_FILES="$_TEMP_FILES $_tmp"
    echo "$_tmp"
}

cleanup_temp() {
    for _f in $_TEMP_FILES; do
        rm -f "$_f" 2>/dev/null
    done
}

# 스크립트 종료 시 임시 파일 정리
trap cleanup_temp EXIT INT TERM
