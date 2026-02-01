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

# feature 목록
features:
  custom_emoji:
    name: "커스텀 이모지 확장"
    description: "커스텀 이모지 기능을 확장합니다."
    dependencies: []

  local_timeline:
    name: "로컬 타임라인 개선"
    description: "로컬 타임라인 UI를 개선합니다."
    dependencies:
      - "custom_emoji"  # feature 키로 참조
```

### 규칙

#### 상속과 병합

- `inherits`로 상속된 feature들과 현재 `features`는 하나의 집합으로 취급됩니다.
- feature 키가 충돌하면 **자식(현재 manifest)이 덮어씁니다.**

#### 의존성

- `dependencies`는 **feature 키 목록**입니다(파일명 아님).
- 상속으로 포함된 feature도 참조할 수 있습니다.
- 적용/제거 시 **위상 정렬** 순서를 따릅니다.
- **순환 의존성**이 발견되면 오류로 종료합니다.

#### `.patch` 파일 포맷

- `git format-patch` 형식(mbox)을 사용합니다.
- 커밋 메타데이터(작성자, 날짜, 메시지)가 포함됩니다.
- 하나의 `.patch` 파일에 여러 커밋이 포함될 수 있습니다.

---

## CLI 명령어

### 초기화 (`init`)

```sh
# 현재 디렉터리에 패치 세트 초기화
uri init

# 특정 Mastodon 버전용 패치 세트 초기화
uri init v4.3.2
```

### 추가 (`add`)

```sh
# uri 버전 추가
uri add v4.3.2 uri1.23

# feature 추가
uri add v4.3.2 uri1.23 custom_emoji

# feature 추가 (옵션 포함)
uri add v4.3.2 uri1.23 custom_emoji \
    --name "커스텀 이모지 확장" \
    --description "커스텀 이모지 기능을 확장합니다." \
    --dependencies "base_feature"
```

### 제거 (`remove`)

```sh
# feature 제거
uri remove v4.3.2 uri1.23 custom_emoji

# uri 버전 제거
uri remove v4.3.2 uri1.23

# Mastodon 버전 패치 세트 삭제
uri remove v4.3.2
```

### 펼치기 (`expand`)

feature를 Mastodon 소스에 적용합니다.

```sh
uri expand v4.3.2 uri1.23 custom_emoji /path/to/mastodon
```

### 접기 (`collapse`)

Mastodon 소스에서 feature를 패치 파일로 추출합니다.

```sh
uri collapse v4.3.2 uri1.23 custom_emoji /path/to/mastodon
```

> **펼치기/접기 동작 원리**
>
> - 각 패치 파일을 커밋으로 변환하여 Git 리포지토리에서 적용/제거합니다.
> - 의존성이 있는 feature들은 함께 처리됩니다(적용은 의존성 순서, 추출은 역순).

### 배포 적용 (`apply`)

uri 버전의 모든 feature를 일괄 적용합니다.

```sh
uri apply v4.3.2 uri1.23 --destination /path/to/mastodon
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
2. 의존성 순서에 따라 feature 적용
3. 각 feature 적용 완료 시 **상태 추적용 Git 브랜치 생성**
   - feature 간 경계를 명확히 하고, 커밋 수를 추적할 수 있습니다

**충돌 처리**: `git merge`와 유사하게 충돌 시 중단하며, `--continue` / `--abort` 옵션을 지원할 예정입니다.

### `collapse` — 패치 추출

1. 상태 추적용 브랜치를 활용하여 feature별 커밋 범위 식별
   - `직전_feature_브랜치..해당_feature_브랜치` 범위로 한정
2. 의존성 역순으로 `.patch` 파일 추출

### `apply` — 배포용 전체 적용

- 지정한 uri 버전의 **모든 feature**를 적용합니다.
- 상속된 feature도 포함되며, 하나의 집합으로 취급됩니다.
- 주로 **배포 목적**으로 사용됩니다.

