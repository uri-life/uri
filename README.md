# Uri Reconstruction Instrument

우리.인생 Mastodon 인스턴스의 패치 세트를 관리하기 위한 도구입니다.

> [!CAUTION]
> 이 리포지토리의 코드는 LLM(Large Language Model) 등 AI 도구를 사용하여 작성되었습니다.
> 코드 리뷰는 부분적으로만 진행되었으므로, 사용 시 주의가 필요합니다.

## 목차

- [존재 이유](#존재-이유)
- [용어](#용어)
- [패치 세트 구조](#패치-세트-구조)
- [CLI 명령어](#cli-명령어)
- [셸 자동 완성](#셸-자동-완성)
- [동작 계약](#동작-계약)

---

## 존재 이유

우리.인생 Mastodon 인스턴스는 여러 커스텀 패치를 적용하여 운영되고 있습니다. 본래 이러한 수정 사항을 기능별로 Git 브랜치로 관리하고 있었으나, 브랜치가 많아지고 복잡해지면서 관리가 어려워졌습니다.

이 도구는 각 수정 사항을 **개별 파일로 분리**하여 관리하고, 필요에 따라 **선택적으로 적용**할 수 있도록 도와줍니다.

---

## 용어

| 용어 | 설명 | 예시 |
|------|------|------|
| **Mastodon 버전** | upstream Mastodon의 버전 태그 | `v4.3.2` |
| **uri 버전** | upstream 버전에 붙는 우리.인생 수정 버전 | `v4.3.2+uri1.23` |
| **feature** | 하나의 기능(수정 사항) 단위 | `custom_emoji` |

> **참고**: 패치 세트 내부에서는 `versions/v4.3.2/patches/uri1.23/`처럼 `+` 뒤의 부분만 디렉터리 이름으로 사용합니다.

---

## 패치 세트 구조

### 디렉터리 레이아웃

```text
/
├── manifest.yaml                      # 루트 manifest
└── versions/
    └── v4.3.2/                        # Mastodon 버전
        └── patches/
            └── uri1.23/               # uri 버전
                ├── manifest.yaml      # uri 버전 manifest
                ├── custom_emoji.patch
                ├── local_timeline.patch
                └── ...
```

### 루트 `manifest.yaml`

```yaml
# Mastodon의 Git 리포지토리 위치
upstream: https://github.com/mastodon/mastodon.git
```

### uri 버전 `manifest.yaml`

```yaml
# 이 uri 버전이 상속하는 다른 uri 버전 (선택, 단일 값)
# - 같은 Mastodon 버전: "uri1.0"
# - 다른 Mastodon 버전: "v4.3.2+uri1.23"
inherits: "uri1.0"

# 이 버전에서 제외할 상속 feature 목록 (선택)
excludes:
  - "legacy_theme"

# feature 목록
features:
  custom_emoji:
    name: "커스텀 이모지 확장"
    description: "커스텀 이모지 기능을 확장합니다."
    dependencies: []
    dev-dependencies: []

  local_timeline:
    name: "로컬 타임라인 개선"
    description: "로컬 타임라인 UI를 개선합니다."
    dependencies:
      - "custom_emoji"  # feature 키로 참조
    dev-dependencies:
      - "debug_toolbar" # expand/collapse에서만 참조
```

### 규칙

#### 상속과 병합

- `inherits`로 상속된 feature들과 현재 `features`는 하나의 집합으로 취급됩니다.
- feature 키가 충돌하면 **자식(현재 manifest)이 덮어씁니다.**
- 각 상속 단계는 현재 `features`를 병합한 뒤 `excludes`에 지정된 상속 feature를 제거합니다.
- `excludes`가 없는 기존 manifest는 빈 배열을 지정한 것처럼 해석됩니다.
- `excludes`는 중복 없는 비어 있지 않은 문자열 배열이어야 하며, 현재 manifest가 직접 선언한 feature에는 사용할 수 없습니다.
- 조상에서 제외된 feature는 더 하위 manifest의 `features`에 다시 선언하여 재도입할 수 있습니다. 패치 파일이 없으면 상속 체인에서 기존 패치를 찾습니다.

#### 의존성

- `dependencies`는 **feature 키 목록**입니다(파일명 아님).
- `dev-dependencies`는 개발용 feature 키 목록이며, 기본 `expand`와 `collapse`에서만 포함됩니다.
- `expand --no-dev`와 `apply`는 `dev-dependencies`를 포함하지 않습니다.
- 상속으로 포함된 feature도 참조할 수 있습니다.
- 최종 활성 feature가 존재하지 않는 `dependencies` 또는 `dev-dependencies`를 참조하면 관련 feature를 나열하고 오류로 종료합니다.
- 적용/제거 시 **위상 정렬** 순서를 따릅니다.
- 위상 정렬에는 시스템 `tsort`가 아니라 저장소의 `libexec/uritsort/`에 포함된 플랫폼별 `uritsort` 실행기를 사용합니다.
- 동시에 적용할 수 있는 feature가 여러 개이면 feature 키의 사전식 순서로 선택하므로, 입력 순서와 무관하게 같은 결과를 냅니다.
- **순환 의존성**이 발견되면 오류로 종료합니다.

지원하는 실행 환경은 다음 네 조합입니다.

| 운영체제 | 아키텍처 | 번들 경로 |
|----------|----------|-----------|
| macOS | ARM64 (`arm64`) | `libexec/uritsort/macos-arm64/uritsort` |
| macOS | x86-64 (`x86_64`) | `libexec/uritsort/macos-x86_64/uritsort` |
| Linux | ARM64 (`arm64`, `aarch64`) | `libexec/uritsort/linux-arm64/uritsort` |
| Linux | x86-64 (`x86_64`, `amd64`) | `libexec/uritsort/linux-x86_64/uritsort` |

지원하지 않는 운영체제·아키텍처 조합이거나 해당 번들 파일이 없거나 실행할 수 없으면 감지된 환경을 표시하고 실패합니다. `PATH`의 `uritsort`나 시스템 `tsort`로 대체하지 않습니다.

#### `.patch` 파일 포맷

- `git format-patch` 형식(mbox)을 사용합니다.
- 커밋 메타데이터(작성자, 날짜, 메시지)가 포함됩니다.
- 하나의 `.patch` 파일에 여러 커밋이 포함될 수 있습니다.

#### apply 전용 해소 패치

`apply`는 feature 패치 옆의 관례적 파일명을 추가로 인식합니다. 이 파일들은 `manifest.yaml`에 등록하지 않습니다.

| 파일명 | 적용 시점 |
|--------|-----------|
| `<feature>~ANTE.patch` | `<feature>.patch` 직전에 항상 적용 |
| `<feature>~POST.patch` | `<feature>.patch` 완료 직후 항상 적용 |
| `<current>~<completed>.patch` | `<current>.patch`가 충돌했고 `<completed>`가 이미 적용된 경우에만, 멈춘 `git am` 워크트리에 적용 |

예시:

```text
versions/v4.3.2/patches/uri1.23/
├── feature-a.patch
├── feature-a~ANTE.patch
├── feature-b.patch
├── feature-b~POST.patch
└── feature-b~feature-a.patch
```

인접한 두 feature의 정상 순서는 `a~ANTE` → `a` → `a~POST` → `b~ANTE` → `b` → `b~POST`입니다. `b.patch`가 충돌하면 이미 완료된 feature를 적용 순서의 역순으로 검사하여 첫 번째 `<b>~<completed>.patch`를 찾고, 그 패치를 충돌 중인 워크트리에 적용한 뒤 관련 파일을 stage하고 `git am --continue`를 시도합니다. pair 패치는 충돌이 실제로 발생했을 때만 적용되며, 별도의 해소 상태 파일이나 manifest 스키마는 사용하지 않습니다.

해소 패치도 일반 패치처럼 상속 체인을 따라 자식 uri 버전에서 부모 uri 버전 순서로 찾습니다. 유지보수자는 필요한 파일을 직접 만들어 같은 패치 디렉터리에 배치합니다.

---

## CLI 명령어

모든 명령어는 `uri <command> --help`로 상세 도움말을 확인할 수 있습니다.

### 초기화 (`init`)

```sh
# 현재 디렉터리에 패치 세트 초기화
uri init

# 특정 Mastodon 버전용 패치 세트 초기화
uri init v4.3.2

# upstream URL 지정
uri init --upstream https://github.com/mastodon/mastodon.git
```

### 추가 (`add`)

```sh
# uri 버전 추가
uri add v4.3.2 uri1.23

# uri 버전 추가 (상속 지정)
uri add v4.3.2 uri1.23 --inherits "uri1.0"

# feature 추가
uri add v4.3.2 uri1.23 custom_emoji

# feature 추가 (옵션 포함)
uri add v4.3.2 uri1.23 custom_emoji \
    --name "커스텀 이모지 확장" \
    --description "커스텀 이모지 기능을 확장합니다." \
    --dependencies "base_feature" \
    --dev-dependencies "debug_feature"
```

### 제거 (`remove`)

`remove`는 현재 manifest가 직접 선언한 feature와 그 패치 파일을 삭제합니다. 상속 feature를 비활성화하려면 `exclude`를 사용합니다.

```sh
# feature 제거
uri remove v4.3.2 uri1.23 custom_emoji

# uri 버전 제거
uri remove v4.3.2 uri1.23

# Mastodon 버전 패치 세트 삭제
uri remove v4.3.2

# 확인 프롬프트 없이 강제 삭제 (-f 또는 --force)
uri remove v4.3.2 uri1.23 custom_emoji -f
```

### 상속 feature 제외와 복원 (`exclude`, `include`)

```sh
# 현재 uri 버전에서 상속 feature 제외
uri exclude v4.3.2 uri1.23 legacy_theme

# 현재 manifest가 직접 제외한 feature를 다시 포함
uri include v4.3.2 uri1.23 legacy_theme
```

`exclude`는 활성화된 상속 feature만 `excludes`에 추가하고 패치 파일은 변경하지 않습니다. 남아 있는 feature의 일반 또는 개발 의존성이 끊기면 manifest를 변경하지 않고 실패합니다.

`include`는 현재 manifest의 `excludes` 항목만 제거합니다. 조상 manifest에서 이미 제외된 feature를 다시 도입하려면 하위 manifest의 `features`에 해당 feature를 직접 선언해야 합니다.

### 목록 (`list`)

```sh
# Mastodon 버전 목록
uri list

# 특정 Mastodon 버전의 uri 패치 목록
uri list v4.3.2

# 특정 uri 버전의 최종 활성 feature 목록 (상속 및 excludes 반영)
uri list v4.3.2 uri1.23
```

### 의존성 그래프 (`graph`)

상속된 feature를 포함하여 특정 uri 버전의 feature 의존성 그래프를 출력합니다. 기본 출력은 터미널에서 보기 좋은 tree 형식이며, `--format dot`으로 Graphviz DOT 형식을 출력할 수 있습니다.

```sh
# 의존성 그래프 출력
uri graph v4.3.2 uri1.23

# 개발 의존성까지 포함
uri graph v4.3.2 uri1.23 --include-dev

# Graphviz DOT 형식으로 출력
uri graph v4.3.2 uri1.23 --format dot
```

### 펼치기 (`expand`)

feature와 그 의존성을 Mastodon 소스에 적용합니다. 기본적으로 `dev-dependencies`도 함께 적용하며, `--no-dev`를 사용하면 배포 적용(`apply`)과 같이 일반 의존성만 적용합니다.

```sh
# feature 적용
uri expand v4.3.2 uri1.23 custom_emoji /path/to/mastodon

# 충돌 해결 후 계속 진행
uri expand /path/to/mastodon --continue

# 진행 중인 작업 중단 및 원복
uri expand /path/to/mastodon --abort

# 이전 apply로 생성된 버전 브랜치를 자동 삭제하고 진행
uri expand v4.3.2 uri1.23 custom_emoji /path/to/mastodon --force

# 개발 의존성을 제외하고 feature 적용
uri expand v4.3.2 uri1.23 custom_emoji /path/to/mastodon --no-dev
```

### 접기 (`collapse`)

Mastodon 소스에서 지정한 feature를 패치 파일로 추출합니다. `dev-dependencies`를 포함한 의존 feature는 각자가 선언한 의존성만 남긴 기반 위로 임시 rebase하여 검증합니다.

기본 모드는 의존 feature의 후보 패치가 현재 패치와 다르면 어떤 패치도 저장하지 않고 중단합니다. 검증이 성공하면 지정한 feature의 패치만 저장합니다. `--recursive`를 사용하면 재귀 의존 feature의 패치도 함께 갱신합니다.

성공한 두 모드 모두 태그 위치로 체크아웃하고 관련 브랜치를 삭제합니다.

```sh
# 지정한 feature만 갱신
uri collapse v4.3.2 uri1.23 custom_emoji /path/to/mastodon

# 의존 feature까지 재귀적으로 갱신
uri collapse v4.3.2 uri1.23 custom_emoji /path/to/mastodon --recursive
```

> **참고**: `collapse`는 `expand`와 달리 `--continue`/`--abort`를 지원하지 않습니다.

### 배포 적용 (`apply`)

uri 버전의 모든 feature를 일괄 적용합니다. 배포 목적 명령이므로 `dev-dependencies`는 적용하지 않습니다.
충돌이 예상되는 조합에는 [apply 전용 해소 패치](#apply-전용-해소-패치)를 둘 수 있습니다.

```sh
# 모든 feature 적용
uri apply v4.3.2 uri1.23 /path/to/mastodon

# 충돌 해결 후 계속 진행
uri apply /path/to/mastodon --continue

# 진행 중인 작업 중단 및 원복
uri apply /path/to/mastodon --abort
```

`--continue`/`--abort`를 위한 작업 상태는 패치 세트나 Mastodon 리포지토리 내부가 아니라 시스템 임시 디렉터리의 `uri/state/` 아래에 저장됩니다.

### 마이그레이션 (`migrate`)

> **일회성 도구**: 브랜치 기반 패치 세트에서 uri 구조로 마이그레이션할 때만 사용합니다.

```sh
uri migrate /path/to/old_mastodon v4.3.2/uri1 23 /path/to/new_mastodon
```

---

## 셸 자동 완성

`uri` CLI는 Bash, Zsh, Fish 셸의 자동 완성을 지원합니다.

`versions/` 디렉터리와 `manifest.yaml`을 실시간 조회하여 mastodon 버전, uri 버전, feature 이름을 동적으로 완성합니다. `exclude`는 활성 상속 feature, `include`는 현재 제외 목록, `remove`는 현재 manifest가 직접 선언한 feature만 제안합니다. feature 동적 완성에는 `yq`가 필요하며, 미설치 시 커맨드·플래그 완성만 동작합니다.

### Bash

`~/.bashrc` 또는 `~/.bash_profile`에 추가:

```bash
source /path/to/uri/share/bash-completion/completions/uri
```

또는 시스템 completions 디렉터리에 복사:

```bash
cp share/bash-completion/completions/uri /usr/local/share/bash-completion/completions/
```

### Zsh

`~/.zshrc`에 추가 (`compinit` 호출 전):

```zsh
fpath=(/path/to/uri/share/zsh/site-functions $fpath)
autoload -Uz compinit && compinit
```

또는 기존 `$fpath` 디렉터리에 심링크:

```zsh
ln -s /path/to/uri/share/zsh/site-functions/_uri /usr/local/share/zsh/site-functions/_uri
```

### Fish

completions 디렉터리에 복사 또는 심링크:

```fish
cp share/fish/vendor_completions.d/uri.fish ~/.config/fish/completions/
# 또는
ln -s (realpath share/fish/vendor_completions.d/uri.fish) ~/.config/fish/completions/uri.fish
```

---

## 동작 계약

### 공통 전제

| 조건 | 설명 |
|------|------|
| Git 리포지토리 | `destination` / `source` 경로는 Git 리포지토리여야 합니다 |
| Clean 워킹 트리 | 미커밋/스테이징 변경이 없어야 합니다 |
| 자동 체크아웃 | 버전 태그 체크아웃은 도구가 자동으로 수행합니다 |

### `expand` — 패치 적용

1. Mastodon 버전 태그를 기준으로 체크아웃
2. 대상 feature와 그 의존성을 위상 정렬하여 순서대로 적용
   - 기본적으로 `dev-dependencies`를 포함하며, `--no-dev` 지정 시 제외합니다
3. 각 feature 적용 완료 시 **상태 추적용 Git 브랜치 생성** (`uri/{ver}/{uri_ver}/{feature}`)
   - feature 간 경계를 명확히 하고, 커밋 범위를 추적할 수 있습니다

**충돌 처리**: `git merge`와 유사하게 충돌 시 중단하며, `--continue` / `--abort` 옵션을 지원합니다.

### `collapse` — 패치 추출

1. 상태 추적용 브랜치와 인접 체크포인트의 merge-base로 feature별 고유 커밋 범위 식별
2. 임시 clone에서 각 feature를 해당 feature의 재귀 `dependencies`/`dev-dependencies`만 적용된 기반 위로 rebase하여 후보 패치 생성
3. 기본 모드는 의존 feature 후보가 현재 유효 패치와 모두 같을 때만 대상 feature 패치를 저장
4. `--recursive`는 모든 재귀 의존 feature 패치까지 저장
5. 성공 후 태그로 체크아웃하고 관련 브랜치를 삭제

후보 생성·rebase·비재귀 검증이 실패하면 패치, manifest, 원본 HEAD와 feature 브랜치를 전혀 변경하지 않습니다.

> **참고**: `collapse`는 충돌 없이 단방향으로 실행되므로 `--continue`/`--abort`를 지원하지 않습니다.

### `apply` — 배포용 전체 적용

- 지정한 uri 버전의 **모든 feature**를 위상 정렬 순서로 적용합니다.
- 상속된 feature를 포함하되 `excludes`로 제거된 feature는 적용하지 않습니다.
- `dev-dependencies`는 포함하지 않습니다.
- 적용 후 `uri/{ver}/{uri_ver}` 브랜치를 생성합니다.
- 주로 **배포 목적**으로 사용됩니다.
- 충돌 시 `--continue` / `--abort`를 지원합니다.
