# Developer Handbook — Orchid Clothes ERP

## 🚀 Run the App Locally

```bash
flutter run -d windows
```

---

## 🧪 Run Tests

```bash
# Quick pass/fail
flutter test

# Verbose expanded output
flutter test --reporter expanded

# Single test file
flutter test test/schema_migration_test.dart
```

---

## 🔧 Regenerate DI / Drift Code

Always run this after adding a new injectable class, table, or DAO:

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## 🪟 Build Windows Release (Local)

```bash
# 1. Enable Windows desktop (only once per machine)
flutter config --enable-windows-desktop

# 2. Build release EXE + DLLs
flutter build windows --release

# Output is in:
# build/windows/x64/runner/Release/
```

---

## 📦 Distribute the Windows App

### Option A — ZIP Artifact (GitHub Actions CI/CD)

Every `git push` to `main` or `dev` automatically triggers the workflow
`.github/workflows/windows_build.yml`, which:

1. Runs `flutter analyze` and `flutter test` on Ubuntu.
2. Builds the Windows release EXE on a `windows-latest` runner.
3. Zips the entire `Release/` folder.
4. Uploads it as a **GitHub Actions Artifact**.

**How to download:**
1. Go to → `https://github.com/osos3lomangy1-dot/clothes_erp/actions`
2. Click the latest workflow run named **"Windows Build & Release"**.
3. Scroll down to **Artifacts** and download `orchid-erp-windows-vX.Y.Z`.
4. Unzip on the target machine and run `clothes_erp.exe`.

> [!IMPORTANT]
> The ZIP must stay together — the EXE requires all the `.dll` files next to it.

---

### Option B — MSIX Installer (Recommended for Deployment)

MSIX is a modern Windows installer format that installs cleanly via double-click.

**Build MSIX locally:**
```bash
# After `flutter build windows --release`
dart run msix:create
# Output: build/windows/x64/runner/Release/clothes_erp.msix
```

**Configuration** is in `pubspec.yaml` under `msix_config:`:
```yaml
msix_config:
  display_name: Orchid Clothes ERP
  publisher_display_name: Orchid ERP
  identity_name: com.example.clothes_erp
  msix_version: 1.0.0.0
  logo_path: windows/runner/resources/app_icon.ico
  capabilities:
    - internetClient
```

> [!NOTE]
> To install a **self-signed MSIX** (for internal/testing distribution without
> the Microsoft Store), the target PC must first trust the developer certificate.
> Run this in PowerShell (Admin):
> ```powershell
> Add-AppxPackage -Path "clothes_erp.msix" -AllowUnsigned
> ```
> Or export and install the certificate from the MSIX using **certmgr.msc**
> and then double-click the `.msix` to install.

**MSIX via CI/CD:**
The GitHub Actions workflow also builds an MSIX (optional step) and uploads it
as a separate artifact `orchid-erp-msix-vX.Y.Z` on every run.

---

## 🔄 CI/CD Workflows

| Workflow File | Trigger | What it Does |
|---|---|---|
| `windows_build.yml` | Push to `main`/`dev`, PR, manual | Analyze → Test → Build Windows → Upload ZIP + MSIX |
| `firebase_app_distribution.yml` | *(disabled)* | Firebase App Distribution is Android-only; not applicable for this Windows app |

---

## 🛠 Common Issues

| Problem | Fix |
|---|---|
| Missing DI annotations | Ensure `@injectable` / `@lazySingleton` on new classes, then run `build_runner` |
| Drift `duplicate column` at runtime | Bump `schemaVersion` in `app_database.dart` and add `m.addColumn(...)` with PRAGMA guard |
| `flutter build windows --release` fails | Run `flutter doctor` and make sure Visual Studio 2022 (with C++ workload) is installed |
| MSIX install blocked | Trust the self-signed cert first (see Option B above) |
| Money precision errors | Always use `int` minor units (piasters), never `double` |
