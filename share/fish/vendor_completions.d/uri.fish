# uri - fish shell completion

# --- 헬퍼 함수 ---

# URI_ROOT 탐색
function __uri_find_root
    set -l dir $PWD
    while test "$dir" != /
        if test -f "$dir/manifest.yaml"
            echo "$dir"
            return 0
        end
        set dir (dirname "$dir")
    end
    return 1
end

# mastodon 버전 목록
function __uri_mastodon_versions
    set -l root (__uri_find_root); or return
    set -l vdir "$root/versions"
    if test -d "$vdir"
        for d in $vdir/*/
            basename "$d"
        end
    end
end

# uri 버전 목록 (mastodon_ver 인자 필요)
function __uri_uri_versions
    set -l mver $argv[1]
    set -l root (__uri_find_root); or return
    set -l pdir "$root/versions/$mver/patches"
    if test -d "$pdir"
        for d in $pdir/*/
            basename "$d"
        end
    end
end

# feature 키 목록 (상속 체인을 따라가며 수집, yq 필요)
function __uri_features
    set -l mver $argv[1]
    set -l uver $argv[2]
    set -l root (__uri_find_root); or return
    if not command -q yq
        return
    end
    __uri_resolve_features "$root" "$mver" "$uver" | sort -u
end

# 상속 체인을 재귀적으로 따라가며 feature 키 수집 (내부 함수)
function __uri_resolve_features
    set -l root $argv[1]
    set -l mver $argv[2]
    set -l uver $argv[3]
    set -l manifest "$root/versions/$mver/patches/$uver/manifest.yaml"
    if not test -f "$manifest"
        return
    end
    yq eval '.features | keys | .[]' "$manifest" 2>/dev/null
    set -l inherits (yq eval '.inherits // ""' "$manifest" 2>/dev/null)
    if test -n "$inherits"
        if string match -q '*+*' -- "$inherits"
            set -l parts (string split '+' -- "$inherits")
            __uri_resolve_features "$root" $parts[1] $parts[2]
        else
            __uri_resolve_features "$root" "$mver" "$inherits"
        end
    end
end

# 커맨드라인에서 위치 인자 추출 (서브커맨드 이후, 플래그 제외)
# argv: 값을 소비하는 플래그 목록 (예: --upstream --name ...)
function __uri_positional_args
    set -l value_flags $argv
    set -l tokens (commandline -opc)
    set -l positionals
    set -l skip_next false
    set -l found_subcmd false

    for i in (seq 2 (count $tokens))
        set -l tok $tokens[$i]
        if test "$skip_next" = true
            set skip_next false
            continue
        end
        if test "$found_subcmd" = false
            # 서브커맨드 찾기
            switch $tok
                case init add remove list expand collapse apply migrate
                    set found_subcmd true
                case '-*'
                    continue
                case '*'
                    set found_subcmd true
            end
            continue
        end
        # 서브커맨드 이후 토큰
        switch $tok
            case '-*'
                if contains -- "$tok" $value_flags
                    set skip_next true
                end
            case '*'
                set -a positionals $tok
        end
    end
    if test (count $positionals) -gt 0
        printf '%s\n' $positionals
    end
end

# 커맨드라인에 플래그가 있는지 확인
function __uri_has_flag
    set -l flag $argv[1]
    set -l tokens (commandline -opc)
    contains -- "$flag" $tokens
end

# 현재 서브커맨드 내 위치 인자 수 반환
function __uri_pos_count
    set -l pos (__uri_positional_args $argv)
    count $pos
end

# n번째 위치 인자 조회
function __uri_get_pos
    set -l n $argv[1]
    set -l flags $argv[2..]
    set -l pos (__uri_positional_args $flags)
    if test (count $pos) -ge $n
        echo $pos[$n]
    end
end


# --- 서브커맨드 없이 최상위 완성 ---
complete -c uri -f -n '__fish_use_subcommand' -a init     -d '패치 세트 초기화'
complete -c uri -f -n '__fish_use_subcommand' -a add      -d 'uri 버전 또는 feature 추가'
complete -c uri -f -n '__fish_use_subcommand' -a remove   -d '버전 또는 feature 제거'
complete -c uri -f -n '__fish_use_subcommand' -a list     -d '버전·feature 목록 출력'
complete -c uri -f -n '__fish_use_subcommand' -a expand   -d 'feature를 Mastodon 소스에 적용'
complete -c uri -f -n '__fish_use_subcommand' -a collapse -d '패치 파일로 추출'
complete -c uri -f -n '__fish_use_subcommand' -a apply    -d '모든 feature 일괄 적용'
complete -c uri -f -n '__fish_use_subcommand' -a migrate  -d '브랜치 기반에서 마이그레이션'
complete -c uri -f -n '__fish_use_subcommand' -s h -l help    -d '도움말'
complete -c uri -f -n '__fish_use_subcommand' -s v -l version -d '버전 출력'

# --- init ---
complete -c uri -f -n '__fish_seen_subcommand_from init' -s h -l help     -d '도움말'
complete -c uri -f -n '__fish_seen_subcommand_from init' -l upstream -x    -d 'upstream Git URL'
complete -c uri -f -n '__fish_seen_subcommand_from init; and test (__uri_pos_count --upstream) -eq 0' \
    -a '(__uri_mastodon_versions)' -d 'Mastodon 버전'

# --- add ---
complete -c uri -f -n '__fish_seen_subcommand_from add' -s h -l help          -d '도움말'
complete -c uri -f -n '__fish_seen_subcommand_from add' -l name         -x    -d 'feature 이름'
complete -c uri -f -n '__fish_seen_subcommand_from add' -l description  -x    -d 'feature 설명'
complete -c uri -f -n '__fish_seen_subcommand_from add' -l dependencies -x    -d '의존 feature'
complete -c uri -f -n '__fish_seen_subcommand_from add' -l inherits     -x    -d '상속할 uri 버전'

complete -c uri -f -n '__fish_seen_subcommand_from add; and test (__uri_pos_count --name --description --dependencies --inherits) -eq 0' \
    -a '(__uri_mastodon_versions)' -d 'Mastodon 버전'
complete -c uri -f -n '__fish_seen_subcommand_from add; and test (__uri_pos_count --name --description --dependencies --inherits) -eq 1' \
    -a '(__uri_uri_versions (__uri_get_pos 1 --name --description --dependencies --inherits))' -d 'uri 버전'
complete -c uri -f -n '__fish_seen_subcommand_from add; and test (__uri_pos_count --name --description --dependencies --inherits) -eq 2' \
    -a '(__uri_features (__uri_get_pos 1 --name --description --dependencies --inherits) (__uri_get_pos 2 --name --description --dependencies --inherits))' -d 'feature'

# --- remove ---
complete -c uri -f -n '__fish_seen_subcommand_from remove' -s h -l help  -d '도움말'
complete -c uri -f -n '__fish_seen_subcommand_from remove' -s f -l force -d '강제 삭제'

complete -c uri -f -n '__fish_seen_subcommand_from remove; and test (__uri_pos_count) -eq 0' \
    -a '(__uri_mastodon_versions)' -d 'Mastodon 버전'
complete -c uri -f -n '__fish_seen_subcommand_from remove; and test (__uri_pos_count) -eq 1' \
    -a '(__uri_uri_versions (__uri_get_pos 1))' -d 'uri 버전'
complete -c uri -f -n '__fish_seen_subcommand_from remove; and test (__uri_pos_count) -eq 2' \
    -a '(__uri_features (__uri_get_pos 1) (__uri_get_pos 2))' -d 'feature'

# --- list ---
complete -c uri -f -n '__fish_seen_subcommand_from list' -s h -l help -d '도움말'

complete -c uri -f -n '__fish_seen_subcommand_from list; and test (__uri_pos_count) -eq 0' \
    -a '(__uri_mastodon_versions)' -d 'Mastodon 버전'
complete -c uri -f -n '__fish_seen_subcommand_from list; and test (__uri_pos_count) -eq 1' \
    -a '(__uri_uri_versions (__uri_get_pos 1))' -d 'uri 버전'

# --- expand ---
complete -c uri -f -n '__fish_seen_subcommand_from expand' -s h -l help     -d '도움말'
complete -c uri -f -n '__fish_seen_subcommand_from expand' -l continue       -d '충돌 해결 후 계속'
complete -c uri -f -n '__fish_seen_subcommand_from expand' -l abort          -d '작업 중단'
complete -c uri -f -n '__fish_seen_subcommand_from expand' -l force          -d '기존 브랜치 삭제'

# --continue/--abort 모드: destination(디렉터리)만
complete -c uri -F -n '__fish_seen_subcommand_from expand; and __uri_has_flag --continue; and test (__uri_pos_count) -eq 0'
complete -c uri -F -n '__fish_seen_subcommand_from expand; and __uri_has_flag --abort; and test (__uri_pos_count) -eq 0'

# 일반 모드
complete -c uri -f -n '__fish_seen_subcommand_from expand; and not __uri_has_flag --continue; and not __uri_has_flag --abort; and test (__uri_pos_count) -eq 0' \
    -a '(__uri_mastodon_versions)' -d 'Mastodon 버전'
complete -c uri -f -n '__fish_seen_subcommand_from expand; and not __uri_has_flag --continue; and not __uri_has_flag --abort; and test (__uri_pos_count) -eq 1' \
    -a '(__uri_uri_versions (__uri_get_pos 1))' -d 'uri 버전'
complete -c uri -f -n '__fish_seen_subcommand_from expand; and not __uri_has_flag --continue; and not __uri_has_flag --abort; and test (__uri_pos_count) -eq 2' \
    -a '(__uri_features (__uri_get_pos 1) (__uri_get_pos 2))' -d 'feature'
complete -c uri -F -n '__fish_seen_subcommand_from expand; and not __uri_has_flag --continue; and not __uri_has_flag --abort; and test (__uri_pos_count) -eq 3'

# --- collapse ---
complete -c uri -f -n '__fish_seen_subcommand_from collapse' -s h -l help -d '도움말'

complete -c uri -f -n '__fish_seen_subcommand_from collapse; and test (__uri_pos_count) -eq 0' \
    -a '(__uri_mastodon_versions)' -d 'Mastodon 버전'
complete -c uri -f -n '__fish_seen_subcommand_from collapse; and test (__uri_pos_count) -eq 1' \
    -a '(__uri_uri_versions (__uri_get_pos 1))' -d 'uri 버전'
complete -c uri -f -n '__fish_seen_subcommand_from collapse; and test (__uri_pos_count) -eq 2' \
    -a '(__uri_features (__uri_get_pos 1) (__uri_get_pos 2))' -d 'feature'
complete -c uri -F -n '__fish_seen_subcommand_from collapse; and test (__uri_pos_count) -eq 3'

# --- apply ---
complete -c uri -f -n '__fish_seen_subcommand_from apply' -s h -l help  -d '도움말'
complete -c uri -f -n '__fish_seen_subcommand_from apply' -l continue    -d '충돌 해결 후 계속'
complete -c uri -f -n '__fish_seen_subcommand_from apply' -l abort       -d '작업 중단'

# --continue/--abort 모드: destination(디렉터리)만
complete -c uri -F -n '__fish_seen_subcommand_from apply; and __uri_has_flag --continue; and test (__uri_pos_count) -eq 0'
complete -c uri -F -n '__fish_seen_subcommand_from apply; and __uri_has_flag --abort; and test (__uri_pos_count) -eq 0'

# 일반 모드
complete -c uri -f -n '__fish_seen_subcommand_from apply; and not __uri_has_flag --continue; and not __uri_has_flag --abort; and test (__uri_pos_count) -eq 0' \
    -a '(__uri_mastodon_versions)' -d 'Mastodon 버전'
complete -c uri -f -n '__fish_seen_subcommand_from apply; and not __uri_has_flag --continue; and not __uri_has_flag --abort; and test (__uri_pos_count) -eq 1' \
    -a '(__uri_uri_versions (__uri_get_pos 1))' -d 'uri 버전'
complete -c uri -F -n '__fish_seen_subcommand_from apply; and not __uri_has_flag --continue; and not __uri_has_flag --abort; and test (__uri_pos_count) -eq 2'

# --- migrate ---
complete -c uri -f -n '__fish_seen_subcommand_from migrate' -s h -l help -d '도움말'

complete -c uri -F -n '__fish_seen_subcommand_from migrate; and test (__uri_pos_count) -eq 0'
complete -c uri -f -n '__fish_seen_subcommand_from migrate; and test (__uri_pos_count) -eq 1'
complete -c uri -f -n '__fish_seen_subcommand_from migrate; and test (__uri_pos_count) -eq 2'
complete -c uri -F -n '__fish_seen_subcommand_from migrate; and test (__uri_pos_count) -eq 3'
