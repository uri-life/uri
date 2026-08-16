# URI Repository Instructions

## Test organization

- Write tests with Swift Testing and place them in the test target that owns the
  behavior under test.
- Group tests by coherent behavioral domain. Reserve `Support` for helpers
  shared across multiple domains; do not put test cases there.
- Use one `@Suite` per `*Tests.swift` file. The file stem and suite type must
  match exactly, and the type must end in `Tests`.
- Give each suite a concise Title Case display name that covers every test in
  the file. Rename the display name, suite type, and file together when the
  suite's responsibility changes.
- Keep every `@Test` inside a suite and preserve any required suite traits. Use
  serialization when tests mutate shared state and cannot safely run in
  parallel.
- Keep test files focused and preferably below roughly 1,000 lines. Split large
  files at coherent behavioral boundaries rather than separating fixtures
  arbitrarily.

Use this shape:

```swift
@Suite("Manifest Decoding")
struct ManifestDecodingTests {
    @Test
    func `an omitted optional field decodes as nil`() {
        // Test body
    }
}
```

## Test names

- Put `@Test` on its own line and write the function name as a descriptive
  English phrase inside backticks.
- Do not use a `test` prefix, a camel-case test name, or a display-name string
  such as `@Test("...")`. Traits and arguments may still be passed to `@Test`.
- Write names in the present tense and start with lowercase unless the first
  word is an exact API, type, key, or protocol spelling.
- Describe the relevant setup or action and the externally observable result.
  Name every material behavior asserted, or split unrelated assertions into
  separate tests.
- Match the strength of the name to the assertions. Do not claim safety,
  stability, completeness, or general support from a single concrete example.
- Prefer product and user-facing vocabulary over helper names or implementation
  details. Preserve the exact spelling and casing of APIs and technical terms.
- Rewrite legacy names from the behavior demonstrated by the test instead of
  mechanically inserting spaces into camel-case identifiers.
- Avoid vague verbs and filler such as `works`, `handles`, `maintains`,
  `honors`, or `uses the expected behavior` when a precise condition and result
  can be stated.
- Keep test names unique within each test target so discovery and filtered runs
  remain unambiguous. Search existing names before adding a test.

## Fixtures and support code

- Keep fixtures and helpers used by one suite in that suite's file and declare
  them `private`.
- Put helpers shared by suites in the same domain in a narrowly named
  `*TestSupport.swift` file. Keep them internal to the test target.
- Put a helper in `Support` only when multiple domains genuinely share it.
- Keep support files free of `@Suite` and `@Test` declarations.
- Do not widen production access or public API solely to share test setup.
- Import only the modules the file uses and follow the surrounding test
  target's import style.

## Validation

- Run the narrowest relevant suite or test filter while iterating.
- Before finishing, list discovered tests and inspect changed suite paths and
  names. A pure move or rename must preserve the leaf-test count exactly; an
  intentional addition or removal must change it by the expected amount.
- Confirm that no legacy suite path, `@Test("...")` display name, `test` prefix,
  camel-case test identifier, duplicate test, or test outside a suite remains
  in the changed scope.
- Treat a successful build with zero matching tests as a failed focused check;
  verify that the intended test names appear in discovery output.
- Run the complete suite from an isolated scratch path, then check the diff for
  whitespace errors:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/uri-clang-cache \
  swift test --disable-sandbox \
  --scratch-path /private/tmp/uri-tests list

CLANG_MODULE_CACHE_PATH=/private/tmp/uri-clang-cache \
  swift test --disable-sandbox \
  --scratch-path /private/tmp/uri-tests

git diff --check
```
