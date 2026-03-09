# 🚀 iOS Reusable CI/CD Workflows (Xcode)

A production-ready reusable **GitHub Actions CI/CD pipeline for native iOS applications built with Xcode**, supporting automated testing, coverage enforcement, archive generation, secure signing, TestFlight deployment, and GitHub release management.

---

## ✨ Features

- Swift Package dependency resolution
- Xcode unit tests with code coverage
- Coverage threshold enforcement
- iOS XCArchive build (unsigned)
- Secure certificate and provisioning profile installation
- IPA export with manual signing
- Apple TestFlight deployment
- GitHub Release creation
- Automatic semantic version conflict resolution
- Optional **“What’s New”** release notes from file

---

## 📦 Repository Structure

```
.github/workflows
├── ios-ci.yml        # Reusable CI workflow
└── ios-release.yml   # Reusable CD workflow
```

---

## 🧠 Architecture Overview

Caller App Repository triggers reusable workflows.

### Reusable CI Workflow (`ios-ci.yml`)

```
Checkout repository
      ↓
Resolve Swift Package dependencies
      ↓
Run Xcode unit tests
      ↓
Generate coverage report
      ↓
Coverage threshold check
      ↓
Build unsigned XCArchive
      ↓
Upload test results and archive artifact
```

### Reusable CD Workflow (`ios-release.yml`)

```
Create GitHub Release
        ↓
Download unsigned archive
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

---

## 🧪 Reusable CI Workflow (`ios-ci.yml`)

### Handles

- Swift Package dependency resolution
- Xcode unit test execution
- Coverage report generation
- Coverage threshold enforcement
- iOS archive build (unsigned)
- Upload test results and build artifacts

### Inputs

- `xcode_version`
- `scheme`
- `workspace`
- `project`
- `configuration`
- `coverage_threshold`
- `build_archive`

### Outputs

- `coverage_percent`

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

```yaml
call-cd-workflow:
  uses: your-org/ios-reusable/.github/workflows/ios-release.yml@main

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
