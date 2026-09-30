# Issue #10 release evidence

**Overall status: PENDING until App Store Connect shows the exact build as
processed and available in TestFlight.**

- Local environment: **BLOCKED for pinned release evidence** -
  `/Applications/Xcode.app` is Xcode 27.0 (27A266a), not the required Xcode
  26.0.1 (17A400). Do not cite a local build as pinned release evidence.
- Workflow run URL: **PENDING**
- Git tag: **PENDING**
- Commit SHA: **PENDING**
- Marketing version: **PENDING**
- TestFlight build number: **PENDING**
- Bundle identifier verified as `com.infinityball.wickettally`: **PENDING**
- Signed archive `UIDeviceFamily` verified as `[1]`: **PENDING**
- Exact Xcode verified as 26.0.1 (17A400), iOS SDK 26.0: **PENDING**
- App Store Connect upload accepted: **PENDING**
- Build processed and available in TestFlight: **PENDING**
- TestFlight build details URL or human-readable App Store Connect location:
  **PENDING**
- Evidence artifact name: **PENDING**
- Screenshot set from this exact build: **PENDING**
- App Store submission: **NOT PERFORMED - MANUAL HUMAN GATE**

## Required evidence

Attach or link:

1. the successful GitHub Actions workflow run;
2. its non-secret `testflight-evidence-*` artifact;
3. an App Store Connect/TestFlight capture showing app name, version, build
   number, processing/availability state, and date;
4. real simulator/device screenshots with model, OS, version/build, commit, and
   workflow run recorded.

Do not attach the IPA, `.xcarchive`, provisioning profiles, certificates, API
keys, or secret values. Do not mark issue #10 complete from an upload command
alone; the cited build must be visible and available in TestFlight. Do not use
output produced by local Xcode 27.0 (27A266a) to satisfy the exact Xcode
26.0.1 (17A400) evidence requirement.
