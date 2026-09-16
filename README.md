# 🚀 iOS Reusable CI/CD Workflows (Xcode)

A production-ready reusable **GitHub Actions CI/CD pipeline for native iOS applications built with Xcode**, supporting automated testing, coverage enforcement, archive generation, secure signing, TestFlight deployment, and GitHub release management.

---

## ✨ Features

### CI — complete quality gate, built entirely from free tooling

| Concern | Tool | Gate |
|---|---|---|
| **Security (SAST)** | **Semgrep OSS** (`r/swift`, `p/secrets` + 16 custom iOS rules: insecure storage, broken TLS, weak crypto, pasteboard/log leakage, WebView bridges) | fails on ERROR |
| **Secret scanning** | **gitleaks** (binary — no org licence needed), with iOS rules for `.p8` keys, provisioning profiles and signing passwords | fails on any leak |
| **Dependency CVEs** | **Trivy** over `Package.resolved` / `Podfile.lock` | report-only by default |
| **Clang analyzer** | `xcodebuild analyze` | opt-in |
| **Dead code** | **Periphery** (whole-project unused declarations) + SwiftLint `unused_declaration` / `unused_import` | report-only by default |
| **Static typing** | `swiftc` with strict concurrency + optional warnings-as-errors | fails on type error |
| **Lint** | **SwiftLint** `--strict` with a shared 60-rule config | fails on any issue |
| **Formatting** | **SwiftFormat** `--lint` | fails on diff |
| **Tests** | `xcodebuild test` via xcbeautify (JUnit report) | fails on any failure |
| **Coverage** | **xccov**, target-filtered, with a line threshold | fails below threshold |

Compiler strictness is injected through **xcodebuild build-setting overrides**, so a
caller repository adopts the whole pipeline **without editing its `.xcodeproj` or
`.xcconfig`**.

### Platform

- Automatic workspace / project / scheme detection
- Simulator resolved by UDID at run time (no hardcoded device that rots on the next Xcode bump)
- SPM, CocoaPods and DerivedData caching
- Parallel CI jobs with an aggregated GitHub job summary
- Secure certificate and provisioning profile installation
- IPA export with manual signing
- Apple TestFlight deployment
- GitHub Release creation
- Automatic semantic version conflict resolution
- Optional **“What’s New”** release notes from file

---

## 📦 Repository Structure

```
.github/
├── workflows/
│   ├── push.yml                 # Reusable iOS CI workflow
│   └── release.yml              # Reusable iOS CD workflow
├── actions/setup-ios/           # Shared setup: pipeline checkout, Xcode,
│   │                            #   project/scheme detection, caching, tools
│   ├── detect_project.sh
│   ├── install_tools.sh
│   └── resolve_dependencies.sh
└── tool/
    ├── .swiftlint.yml           # Shared SwiftLint config (lint + unused-code)
    ├── .swiftformat             # Shared SwiftFormat config
    ├── .periphery.yml           # Dead-code retention rules
    ├── gitleaks.toml            # Secret-scanning rules + iOS allowlists
    ├── semgrep/ios-rules.yml    # Swift/iOS SAST rules
    └── scripts/                 # Summarisers wired into the job summary
        ├── coverage_summary.sh
        ├── junit_summary.sh
        ├── lint_summary.sh
        ├── periphery_summary.sh
        ├── resolve_destination.sh
        ├── xcodebuild_flags.sh
        └── generate_summary_md.sh
```

---

## 🧠 Architecture Overview

Caller App Repository triggers reusable workflows.

### Reusable CI Workflow (`push.yml`)

Five independent jobs run in parallel, then archive and summary:

```
              ┌─ Lint & Format ──── SwiftLint --strict + SwiftFormat --lint
              │                     (no Xcode build)
              │
              ├─ Security ───────── gitleaks + Semgrep + Trivy
Checkout      │                     (runs on ubuntu — 1x billing)
+ setup-ios ──┤
(every job)   ├─ Dead Code ──────── Periphery
              │
              ├─ Clang Analyzer ─── xcodebuild analyze (opt-in)
              │
              └─ Tests & Coverage ─ xcodebuild test + xccov gate
                                              ↓
                                    Build unsigned XCArchive
                                              ↓
                                    CI Summary (job summary + artifacts)
```

Only **Archive** depends on **Tests** — everything else fans out, so a formatting
failure and a coverage failure surface in the same run rather than one at a time.

### 💰 Runner cost

GitHub bills macOS runners at **10x**. Three stages compile the project (tests,
dead code, archive); the clang analyzer would be a fourth, which is why it is
opt-in. The security stage needs no Xcode at all, so it defaults to
`ubuntu-latest` at 1x — override with `security_runner` if your repo is private
to a macOS-only runner pool.

### Reusable CD Workflow (`release.yml`)

```
Create GitHub Release
        ↓
Download unsigned archive (from the caller's own CI job -- see below)
        ↓
Install signing certificate
        ↓
Install provisioning profile
        ↓
Export signed IPA
        ↓
Upload to TestFlight
        ↓
Upload IPA to GitHub Release
```

This workflow does **not** run its own CI pass. It consumes the
`ios-archive-unsigned` artifact the caller's own CI job already built earlier
in the same workflow run — see "Consolidated CI+CD build" below.

---

## Consolidated CI+CD build

Earlier versions of this pipeline had `release.yml` re-run the entire CI
workflow itself (tests + all quality gates + archive) before creating the
release, on top of whatever CI pass the caller's own `push.yml` already ran
to gate the push. For a release-tag push that meant the exact same
build (same scheme, same `configuration: "Release"`, same everything) ran
twice back-to-back for no benefit.

`release.yml` no longer runs a nested CI job. The caller's own `ci` job must
set `build_archive: true` (as this pipeline's example caller already does on
every push, not just release tags) so its archive is available; `cd` then
just downloads that same artifact, signs it, and ships it:

```yaml
# caller's push.yml
ci:
  uses: your-org/ios-reusable/.github/workflows/push.yml@main
  with:
    configuration: "Release"
    build_archive: true
    # ...

cd:
  uses: your-org/ios-reusable/.github/workflows/release.yml@main
  if: contains(github.ref_name, 'release')
  needs: [ci]
  with:
    # ...
```

No second compile, no second test run — `cd` only does release-specific work
(GitHub Release, signing, TestFlight upload).

---

## 🧪 Reusable CI Workflow (`push.yml`)

### Inputs

#### Project

| Input | Default | Description |
|------|---------|-------------|
| `xcode_version` | `latest-stable` | Xcode to select |
| `scheme` | *auto* | Xcode scheme. Auto-detected from the project when empty |
| `workspace` | *auto* | Path to `.xcworkspace` |
| `project` | *auto* | Path to `.xcodeproj` |
| `configuration` | `Release` | Build configuration |
| `runner` | `macos-latest` | Runner for the Xcode stages |
| `security_runner` | `ubuntu-latest` | Runner for the security stage (1x billing) |

#### Stage toggles

| Input | Default | Description |
|------|---------|-------------|
| `run_tests` | `true` | `xcodebuild test` |
| `run_coverage` | `true` | xccov report + threshold gate |
| `run_static_analysis` | `true` | SwiftLint — **previously a no-op placeholder, now a real gate** |
| `run_formatting` | `true` | SwiftFormat |
| `run_security` | `true` | gitleaks + Semgrep |
| `run_dependency_audit` | `true` | Trivy over the lockfiles |
| `run_dead_code` | `true` | Periphery |
| `run_clang_analyzer` | `false` | `xcodebuild analyze` (a 4th compile on a 10x runner) |
| `build_archive` | `true` | Unsigned `.xcarchive` |

#### Tuning

| Input | Default | Description |
|------|---------|-------------|
| `coverage_threshold` | `"0"` | Minimum LINE coverage %. `0` disables the gate |
| `coverage_include_targets` | `""` | Regex of coverage targets to include |
| `coverage_exclude_targets` | `([Tt]ests?\|UITests\|Mock\|Fixture)` | Regex of targets to exclude |
| `test_destination` | *auto* | `-destination`. Auto-resolved to the newest iPhone simulator, pinned by UDID |
| `test_plan` | `""` | Optional `-testPlan` |
| `swift_strict_concurrency` | `targeted` | `off` / `minimal` / `targeted` / `complete` |
| `swift_warnings_as_errors` | `false` | Promote Swift + clang warnings to errors |

#### Gates

Each gate turns its stage from *blocking* into *report-only*. Defaults are chosen
so a repo adopting the pipeline is not blocked on day one by pre-existing debt.

| Input | Default | Blocks the build? |
|------|---------|-------------------|
| `fail_on_lint` | `true` | SwiftLint findings |
| `fail_on_formatting` | `true` | Formatting differences |
| `fail_on_security` | `true` | Semgrep ERRORs and leaked secrets |
| `fail_on_vulnerabilities` | `false` | HIGH/CRITICAL dependency CVEs |
| `fail_on_dead_code` | `false` | Unused declarations |
| `fail_on_clang_analyzer` | `false` | Clang analyzer findings |

#### Secrets

| Secret | Required | Description |
|------|----------|-------------|
| `PIPELINE_TOKEN` | No | Only when **this** pipeline repo is private and the caller lives in a different repo. The default `GITHUB_TOKEN` is scoped to the caller and will 403 when checking out the shared tool configs. |

### Outputs

| Output | Description |
|------|-------------|
| `coverage_percent` | Computed xccov LINE coverage percent |
| `scheme` | The Xcode scheme that was built |

---

## 📊 Coverage

1. `xcodebuild test -enableCodeCoverage YES` produces an `.xcresult`
2. `xcrun xccov view --report --json` is parsed with `jq`
3. Test bundles and `Mock`/`Fixture` targets are filtered out, then covered and
   executable lines are summed across the remaining targets
4. The result is compared against `coverage_threshold`

```
Coverage: 72.86% line (1020/1400 lines across 2 target(s), threshold 70%)
    MyApp.app: 78% (780/1000)
    CoreKit.framework: 60% (240/400)
```

Two deliberate behaviours:

- **The filter refuses to report a figure computed from zero targets.** If your
  include/exclude patterns match nothing, the stage errors instead of silently
  reporting `0%` (or, worse, a number taken from the wrong column).
- **Line coverage only.** `xccov` carries no branch data — unlike JaCoCo on
  Android, there is no branch-coverage gate to offer here. That is a platform
  limitation, not an omission.

---

## 🧭 Adoption path

The pipeline is deliberately loud but not immediately blocking on the noisy
checks. A sensible rollout:

1. **Run it as-is.** Lint, formatting, tests and coverage gate from day one;
   CVEs and dead code report only.
2. **Triage the Periphery report.** Tune retention in `.periphery.yml` for your
   `@objc` surface, storyboards and previews, then set `fail_on_dead_code: true`.
3. **Triage the CVE report**, then set `fail_on_vulnerabilities: true`.
4. **Clear the Swift warning backlog**, then set `swift_warnings_as_errors: true`.
5. **Move `swift_strict_concurrency` to `complete`** when you adopt Swift 6.

To fix formatting locally:

```bash
swiftformat .
```

Any config can be overridden per-repo: commit your own `.swiftlint.yml`,
`.swiftformat` or `.periphery.yml` at the repo root and the pipeline uses it
instead of the shared one.

---

## 🚀 Reusable CD Workflow (`ios-release.yml`)

### Handles

- GitHub Release creation
- iOS signing with certificate and provisioning profile
- IPA export from archive
- TestFlight upload
- Upload IPA artifact to GitHub Release
- Optional **“What’s New”** release notes

### Inputs

- `version`
- `deploy_to_testflight`
- `ios_bundle_id`
- `enable_whats_new`
- `whats_new_file`
- `xcode_version`, `scheme`, `workspace`, `project`, `configuration`,
  `coverage_threshold` — forwarded to the CI stage

> **Note:** `release.yml` now runs `push.yml` as its first job. Previously it did
> not, which meant a release could ship without tests ever running, and the
> `ios-archive-unsigned` artifact it tried to download was never produced in the
> same workflow run.

---

## 📝 “What’s New” (Release Notes from File)

Create a file in your app repository:

```
release_notes.txt
```

Example content:

```
- Added onboarding flow
- Improved login performance
- Fixed crash on iOS 17
```

Enable it in your caller workflow:

```yaml
enable_whats_new: true
whats_new_file: release_notes.txt
```

These release notes will automatically be included when uploading builds to **TestFlight**.

---

## 🍎 iOS Support

- Xcode unit test execution
- Code coverage reporting and validation
- XCArchive build generation
- Manual provisioning profile signing
- P12 certificate signing
- IPA export for App Store distribution
- App Store Connect API authentication
- TestFlight upload
- GitHub Release artifact upload

---

## 🔐 Required Secrets

### iOS Signing

- `IOS_CERT_P12_BASE64`
- `IOS_CERT_PASSWORD`
- `IOS_PROVISION_PROFILE_BASE64`
- `IOS_TEAM_ID`

### App Store Connect

- `APPSTORE_ISSUER_ID`
- `APPSTORE_KEY_ID`
- `APPSTORE_PRIVATE_KEY`

---

## 🧩 Example Caller Workflow Usage

`call-cd-workflow` needs `call-ci-workflow` to have already run with
`build_archive: true` -- see "Consolidated CI+CD build" above.

```yaml
call-ci-workflow:
  uses: your-org/ios-reusable/.github/workflows/push.yml@main
  with:
    configuration: "Release"
    build_archive: true
    # ...

call-cd-workflow:
  uses: your-org/ios-reusable/.github/workflows/ios-release.yml@main
  needs: call-ci-workflow

  with:
    version: 1.2.0
    deploy_to_testflight: true
    ios_bundle_id: com.example.app
    enable_whats_new: true
    whats_new_file: release_notes.txt

  secrets:
    IOS_TEAM_ID: ${{ secrets.IOS_TEAM_ID }}
    IOS_CERT_P12_BASE64: ${{ secrets.IOS_CERT_P12_BASE64 }}
    IOS_CERT_PASSWORD: ${{ secrets.IOS_CERT_PASSWORD }}
    IOS_PROVISION_PROFILE_BASE64: ${{ secrets.IOS_PROVISION_PROFILE_BASE64 }}

    APPSTORE_ISSUER_ID: ${{ secrets.APPSTORE_ISSUER_ID }}
    APPSTORE_KEY_ID: ${{ secrets.APPSTORE_KEY_ID }}
    APPSTORE_PRIVATE_KEY: ${{ secrets.APPSTORE_PRIVATE_KEY }}
```

---

## 📁 Example App Repository Layout

```
your-ios-app
├── MyApp.xcodeproj
├── MyApp.xcworkspace
├── release_notes.txt
└── .github/workflows
    └── main.yml
```

---

## 🏗️ Design Principles

- Fully reusable
- Secure secret handling
- Modular pipeline design
- CI and CD separated
- iOS build and deployment ready
- App Store compliant workflow
- Optional deployment configuration
- No certificates stored in repository

---

## 🧭 Roadmap

- Firebase App Distribution
- Slack notifications
- PR preview builds
- Automatic TestFlight tester assignment
- App Store submission automation
- Multi-language release notes

---

## 🤝 Contributing

Pull requests are welcome for:

- Bug fixes
- Performance improvements
- Additional integrations
- Documentation improvements

---

## 📜 License

MIT License

---

## ⭐ Why use this?

Because it is:

- Fully automated
- Secure
- Reusable across multiple iOS projects
- TestFlight ready
- GitHub Release integrated
- Enterprise-ready
