#!/bin/sh
# list.sh - list 명령 구현
# POSIX 호환 셸 스크립트

# list 명령 사용법 출력
list_usage() {
    cat <<EOF
사용법: uri list [mastodon_version] [uri_version] [옵션]

버전, 패치, feature 목록을 출력합니다.

인자:
  mastodon_version   Mastodon 버전 (예: v4.3.2)
  uri_version        uri 버전 (예: uri1.23)

옵션:
  -h, --help         이 도움말을 출력합니다

예시:
  uri list                       # 모든 Mastodon 버전 목록
  uri list v4.3.2                # v4.3.2의 uri 패치 목록
  uri list v4.3.2 uri1.23        # uri1.23의 feature 목록
EOF
}

# list 명령 메인 함수
cmd_list() {
    _mastodon_ver=""
    _uri_ver=""

    # 옵션 파싱 (--help는 uri_root 확인 전에 처리)
    for _arg in "$@"; do
        case "$_arg" in
            -h|--help)
                list_usage
                exit 0
                ;;
        esac
    done

    require_uri_root

    # 옵션 파싱
    while [ $# -gt 0 ]; do
        case "$1" in
            -*)
                die "알 수 없는 옵션: $1"
                ;;
            *)
                # 위치 인자
                if [ -z "$_mastodon_ver" ]; then
                    _mastodon_ver="$1"
                elif [ -z "$_uri_ver" ]; then
                    _uri_ver="$1"
                else
                    die "인자가 너무 많습니다: $1"
                fi
                ;;
        esac
        shift
    done

    # 인자에 따라 분기
    if [ -z "$_mastodon_ver" ]; then
        _list_versions
    elif [ -z "$_uri_ver" ]; then
        _list_patches "$_mastodon_ver"
    else
        _list_features "$_mastodon_ver" "$_uri_ver"
    fi
}

# 버전 목록 출력 (내부 함수)
_list_versions() {
    _versions_dir="${URI_ROOT}/versions"

    if [ ! -d "$_versions_dir" ]; then
        info "버전이 없습니다."
        return
    fi

    _count=0
    for _ver_path in "$_versions_dir"/*; do
        if [ -d "$_ver_path" ]; then
            _ver=$(basename "$_ver_path")
            echo "$_ver"
            _count=$((_count + 1))
        fi
    done

    if [ $_count -eq 0 ]; then
        info "버전이 없습니다."
    fi
}

# 패치 목록 출력 (내부 함수)
_list_patches() {
    _mastodon_ver="$1"
    _ver_dir=$(version_dir "$_mastodon_ver")
    _patches_dir="${_ver_dir}/patches"

    if [ ! -d "$_ver_dir" ]; then
        die "Mastodon 버전 $_mastodon_ver 가 존재하지 않습니다."
    fi

    if [ ! -d "$_patches_dir" ]; then
        info "패치가 없습니다."
        return
    fi

    _count=0
    for _patch_path in "$_patches_dir"/uri*; do
        if [ -d "$_patch_path" ]; then
            _patch=$(basename "$_patch_path")
            echo "$_patch"
            _count=$((_count + 1))
        fi
    done

    if [ $_count -eq 0 ]; then
        info "패치가 없습니다."
    fi
}

# feature 목록 출력 (내부 함수)
_list_features() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _uri_dir=$(uri_version_dir "$_mastodon_ver" "$_uri_ver")
    _manifest="${_uri_dir}/manifest.yaml"

    if [ ! -d "$_uri_dir" ]; then
        die "uri 버전 $_uri_ver 가 존재하지 않습니다. (Mastodon $_mastodon_ver)"
    fi

    if [ ! -f "$_manifest" ]; then
        die "manifest.yaml을 찾을 수 없습니다: $_manifest"
    fi

    # yq로 features 키 목록 추출
    _features=$(yq -r '.features // {} | keys | .[]' "$_manifest" 2>/dev/null)

    if [ -z "$_features" ]; then
        info "feature가 없습니다."
        return
    fi

    echo "$_features"
}
