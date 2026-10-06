# Release candidate and TestFlight handoff

This directory defines the release process; it is not release evidence. Until a
real workflow run succeeds and App Store Connect shows the processed build, the
release status is **PENDING**.

## Pipeline scope

`.github/workflows/release.yml` is a manually dispatched, tag-only pipeline. It:

1. requires an explicit `UPLOAD` confirmation and the protected `testflight`
   GitHub Environment;
2. blocks unless the Apple runner has exactly Xcode 26.0.1 (17A400) and iOS SDK
   26.0, matching `toolchain.json`;
3. consumes GitHub secret names `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, and
   `ASC_TEAM_ID` without printing their values;
4. creates an automatically signed App Store archive for
   `com.infinityball.wickettally`;
5. verifies the archive signature, bundle identifier, exact
   `UIDeviceFamily = [1]`, marketing version, and build number;
6. exports a signed IPA locally and uploads the verified archive via Xcode 26's
   `xcodebuild -exportArchive` TestFlight upload destination;
7. polls App Store Connect for the exact version/build uploaded during this run,
   then records the processed build ID and non-secret evidence. If processing
   fails or times out, the release run fails. Tester availability remains
   pending human verification.

The workflow does not submit a build for App Review, choose phased release,
release to the App Store, or modify App Store metadata. Those actions are a
manual human gate.

## Current local environment blocker

The local `/Applications/Xcode.app` is Xcode 27.0 (build 27A266a), while the
repository release policy requires exactly Xcode 26.0.1 (build 17A400). A local
archive or simulator run from this machine therefore **must not be represented
as pinned release evidence**, even if it otherwise builds successfully.

Release evidence must come from an Apple runner or other environment that
measures exactly Xcode 26.0.1 (17A400) and iOS SDK 26.0. Until such a run exists,
the exact-toolchain release gate is **BLOCKED/PENDING**. Do not substitute Xcode
27.0, relax the pin, or relabel local output as equivalent evidence.

## One-time GitHub and Apple setup

1. In App Store Connect, confirm the app record uses bundle ID
   `com.infinityball.wickettally`.
2. Create an App Store Connect API key with only the access required to upload
   builds. Store its values as GitHub Actions secrets:
   `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the complete `.p8` contents),
   and `ASC_TEAM_ID`.
3. Never paste secret values into issues, pull requests, workflow inputs,
   artifacts, or evidence documents.
4. Create a GitHub Environment named `testflight`. Add required reviewers so
   the signed upload cannot begin without human approval. Keep the four
   credentials as repository secrets, as required by issue #10.
5. Confirm the Apple Developer team permits automatic signing and has a usable
   App Store distribution/cloud-managed certificate and provisioning profile.
   Missing signing access is a release blocker, not a reason to weaken signing.

## Create and run a release candidate

The marketing version is SemVer and the App Store build number is a positive,
globally increasing integer. A release-candidate tag is:

```text
v<MAJOR>.<MINOR>.<PATCH>-rc.<BUILD_NUMBER>
```

Example for marketing version `0.1.0`, build `42`:

```bash
git tag -a v0.1.0-rc.42 -m "Wicket Tally 0.1.0 release candidate 42"
git push origin v0.1.0-rc.42
```

Then:

1. Open **Actions > Release candidate to TestFlight > Run workflow**.
2. Select the release-candidate tag, not a branch.
3. Enter marketing version `0.1.0`, build number `42`, and select `UPLOAD`.
4. Review and approve the `testflight` Environment deployment.
5. Wait for the upload step to finish. This proves only that App Store Connect
   accepted the upload; it does not prove TestFlight processing succeeded.
6. In App Store Connect, confirm the exact version/build is processed and
   available in TestFlight. Check encryption/export-compliance prompts and
   resolve any processing warning.
7. Complete `evidence-template.md` with the workflow run URL and the exact
   processed TestFlight build. Paste that evidence into issue #10.

Do not reuse or move a release-candidate tag. If the archive or upload fails,
fix the cause, increment the build number, and create a new tag.

## Manual App Store submission gate

After TestFlight testing and only with human approval:

1. validate the metadata draft against the shipped build;
2. replace every screenshot placeholder with a real simulator or device
   capture from that build;
3. verify the App Privacy answers and privacy manifest;
4. select the approved TestFlight build in App Store Connect;
5. complete compliance, pricing, availability, review contact, and review notes;
6. manually click **Add for Review/Submit for Review**.

For a publicly released version, create `v<MAJOR>.<MINOR>.<PATCH>` on the exact
approved commit only after the release decision. The workflow intentionally
does not create or push tags.

## Current evidence status

| Evidence | Status |
| --- | --- |
| Local pinned-toolchain evidence | **BLOCKED - local Xcode is 27.0 (27A266a), not pinned 26.0.1 (17A400)** |
| Real release workflow run URL | **PENDING** |
| Signed archive verification from that run | **PENDING** |
| App Store Connect upload acceptance | **PENDING** |
| Processed TestFlight version/build | **PENDING** |
| Real App Store screenshots | **PENDING** |
| App Store submission | **MANUAL GATE - NOT PERFORMED** |
