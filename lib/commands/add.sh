#!/bin/sh
# add.sh - add 명령 구현
# POSIX 호환 셸 스크립트

# add 명령 사용법 출력
add_usage() {
    cat <<EOF
사용법: uri add <mastodon_version> [uri_version] [feature] [옵션]

uri 버전 또는 feature를 추가합니다.

인자:
  mastodon_version   Mastodon 버전 (예: v4.3.2)
  uri_version        uri 버전 (예: uri1.23)
  feature            feature 이름 (예: custom_emoji)

옵션:
  -h, --help             이 도움말을 출력합니다
  --name NAME            feature 이름 (표시용)
  --description DESC     feature 설명
  --dependencies DEPS    의존하는 feature (쉼표 구분)
  --inherits VERSION     상속할 uri 버전

예시:
  uri add v4.3.2 uri1.23                           # uri 버전 추가
  uri add v4.3.2 uri1.23 custom_emoji              # feature 추가
  uri add v4.3.2 uri1.23 custom_emoji \\
      --name "커스텀 이모지" \\
      --description "이모지 기능 확장" \\
      --dependencies "base"                        # 옵션 포함
EOF
}

# add 명령 메인 함수
cmd_add() {
    require_uri_root

    _mastodon_ver=""
    _uri_ver=""
    _feature=""
    _name=""
    _description=""
    _dependencies=""
    _inherits=""

    # 옵션 파싱
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                add_usage
                exit 0
                ;;
            --name)
                shift
                _name="$1"
                ;;
            --description)
                shift
                _description="$1"
                ;;
            --dependencies)
                shift
                _dependencies="$1"
                ;;
            --inherits)
                shift
                _inherits="$1"
                ;;
            -*)
                die "알 수 없는 옵션: $1"
                ;;
            *)
                # 위치 인자
                if [ -z "$_mastodon_ver" ]; then
                    _mastodon_ver="$1"
                elif [ -z "$_uri_ver" ]; then
                    _uri_ver="$1"
                elif [ -z "$_feature" ]; then
                    _feature="$1"
                else
                    die "인자가 너무 많습니다: $1"
                fi
                ;;
        esac
        shift
    done

    # 필수 인자 확인
    if [ -z "$_mastodon_ver" ]; then
        die "mastodon_version이 필요합니다. 'uri add --help'를 참조하세요."
    fi

    # mastodon 버전 디렉터리 확인
    _ver_dir=$(version_dir "$_mastodon_ver")
    if [ ! -d "$_ver_dir" ]; then
        die "Mastodon 버전 $_mastodon_ver 가 존재하지 않습니다. 'uri init $_mastodon_ver'를 먼저 실행하세요."
    fi

    if [ -z "$_uri_ver" ]; then
        die "uri_version이 필요합니다. 'uri add --help'를 참조하세요."
    fi

    # uri 버전 추가 또는 feature 추가
    if [ -z "$_feature" ]; then
        _add_uri_version "$_mastodon_ver" "$_uri_ver" "$_inherits"
    else
        _add_feature "$_mastodon_ver" "$_uri_ver" "$_feature" "$_name" "$_description" "$_dependencies"
    fi
}

# uri 버전 추가 (내부 함수)
_add_uri_version() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _inherits="$3"

    _uri_dir=$(uri_version_dir "$_mastodon_ver" "$_uri_ver")
    _manifest="${_uri_dir}/manifest.yaml"

    if [ -d "$_uri_dir" ]; then
        die "uri 버전이 이미 존재합니다: $_uri_dir"
    fi

    info "uri 버전 $_uri_ver 를 추가합니다..."

    # 디렉터리 생성
    mkdir -p "$_uri_dir"

    # manifest 생성
    cat > "$_manifest" <<EOF
# uri 버전: ${_mastodon_ver}+${_uri_ver}
EOF

    # inherits 추가 (있는 경우)
    if [ -n "$_inherits" ]; then
        echo "inherits: \"$_inherits\"" >> "$_manifest"
    fi

    # features 섹션 추가
    echo "" >> "$_manifest"
    echo "features: {}" >> "$_manifest"

    success "uri 버전 추가 완료: $_uri_dir"
}

# feature 추가 (내부 함수)
_add_feature() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _feature="$3"
    _name="$4"
    _description="$5"
    _dependencies="$6"

    _uri_dir=$(uri_version_dir "$_mastodon_ver" "$_uri_ver")
    _manifest="${_uri_dir}/manifest.yaml"
    _patch_file="${_uri_dir}/${_feature}.patch"

    # uri 버전 존재 확인
    if [ ! -d "$_uri_dir" ]; then
        die "uri 버전이 존재하지 않습니다: $_uri_dir. 'uri add $_mastodon_ver $_uri_ver'를 먼저 실행하세요."
    fi

    # feature 중복 확인
    if yaml_has "$_manifest" ".features.$_feature"; then
        die "feature가 이미 존재합니다: $_feature"
    fi

    info "feature $_feature 를 추가합니다..."

    # 기본값 설정
    if [ -z "$_name" ]; then
        _name="$_feature"
    fi
    if [ -z "$_description" ]; then
        _description=""
    fi

    # feature 추가 (yq 사용)
    yq eval -i ".features.$_feature = {}" "$_manifest"
    yq eval -i ".features.$_feature.name = \"$_name\"" "$_manifest"
    yq eval -i ".features.$_feature.description = \"$_description\"" "$_manifest"

    # dependencies 추가
    if [ -n "$_dependencies" ]; then
        # 쉼표 구분을 배열로 변환
        _dep_array="["
        _first=true
        # IFS를 쉼표로 설정하여 분리
        _old_ifs="$IFS"
        IFS=','
        for _dep in $_dependencies; do
            # 앞뒤 공백 제거
            _dep=$(echo "$_dep" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ "$_first" = true ]; then
                _dep_array="${_dep_array}\"$_dep\""
                _first=false
            else
                _dep_array="${_dep_array}, \"$_dep\""
            fi
        done
        IFS="$_old_ifs"
        _dep_array="${_dep_array}]"

        yq eval -i ".features.$_feature.dependencies = $_dep_array" "$_manifest"
    else
        yq eval -i ".features.$_feature.dependencies = []" "$_manifest"
    fi

    # 빈 패치 파일 생성
    : > "$_patch_file"

    success "feature 추가 완료: $_feature"
    info "패치 파일: $_patch_file"
}
