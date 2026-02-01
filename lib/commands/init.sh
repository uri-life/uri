#!/bin/sh
# init.sh - init 명령 구현
# POSIX 호환 셸 스크립트

# init 명령 사용법 출력
init_usage() {
    cat <<EOF
사용법: uri init [옵션] [mastodon_version]

패치 세트를 초기화합니다.

인자:
  mastodon_version   초기화할 Mastodon 버전 (예: v4.3.2)
                     생략 시 루트 manifest만 생성

옵션:
  -h, --help         이 도움말을 출력합니다
  --upstream URL     upstream Git URL (기본: https://github.com/mastodon/mastodon.git)

예시:
  uri init                      # 루트 manifest 초기화
  uri init v4.3.2               # v4.3.2용 패치 세트 구조 생성
EOF
}

# init 명령 메인 함수
cmd_init() {
    _upstream="https://github.com/mastodon/mastodon.git"
    _mastodon_ver=""

    # 옵션 파싱
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                init_usage
                exit 0
                ;;
            --upstream)
                shift
                _upstream="$1"
                ;;
            -*)
                die "알 수 없는 옵션: $1"
                ;;
            *)
                if [ -z "$_mastodon_ver" ]; then
                    _mastodon_ver="$1"
                else
                    die "인자가 너무 많습니다: $1"
                fi
                ;;
        esac
        shift
    done

    # 이미 초기화되어 있는지 확인
    if set_uri_root_if_exists; then
        if [ -z "$_mastodon_ver" ]; then
            die "이미 초기화되어 있습니다: ${URI_ROOT}/manifest.yaml"
        fi
        # 버전 추가 모드로 진행
        _init_version "$_mastodon_ver"
        return
    fi

    # 새로 초기화
    _root="$PWD"
    _manifest="${_root}/manifest.yaml"

    # 루트 manifest 생성
    info "패치 세트를 초기화합니다..."
    cat > "$_manifest" <<EOF
# Uri Reconstruction Instrument 패치 세트
# Mastodon 커스텀 패치 관리

upstream: ${_upstream}
EOF

    # versions 디렉터리 생성
    mkdir -p "${_root}/versions"

    success "초기화 완료: $_manifest"

    # mastodon 버전이 지정된 경우 버전 구조도 생성
    if [ -n "$_mastodon_ver" ]; then
        URI_ROOT="$_root"
        export URI_ROOT
        _init_version "$_mastodon_ver"
    fi
}

# 버전 디렉터리 구조 생성 (내부 함수)
_init_version() {
    _ver="$1"
    _ver_dir=$(version_dir "$_ver")

    if [ -d "$_ver_dir" ]; then
        info "버전 디렉터리가 이미 존재합니다: $_ver_dir"
        return
    fi

    info "버전 $_ver 구조를 생성합니다..."

    # 디렉터리 생성
    mkdir -p "${_ver_dir}/patches"

    success "버전 구조 생성 완료: $_ver_dir"
}
