# App Store metadata draft

**Status: DRAFT. Screenshots and build-specific claims are PENDING a real
simulator/device run of the exact TestFlight build.**

## App identity

- **Name:** Wicket Tally
- **Bundle ID:** `com.infinityball.wickettally`
- **Primary category draft:** Sports
- **Secondary category draft:** Utilities
- **Platform:** iPhone only

## Subtitle draft

Plan local cricket match days

## Promotional text draft

Organize leagues, teams, players, grounds, and fixtures on one iPhone, with
local reminders and no account required.

## Description draft

Wicket Tally is a local-first organizer for community cricket.

Create leagues and tournaments, add teams and players, schedule fixtures at
your grounds, and review possible time conflicts before match day. Optional
fixture reminders are scheduled locally on your iPhone.

Your cricket data stays on your device. Wicket Tally has no account, no ads,
no analytics, and no cloud service.

Current release-candidate features:

- Create and manage leagues and tournaments
- Add teams, team colors, and player roles
- Schedule fixtures, grounds, and local reminders
- Warn about overlapping fixture details
- Archive or remove setup records with deletion previews
- Use Dynamic Type and VoiceOver-labelled controls

Before submission, compare every bullet with the exact uploaded build and
remove any claim not directly demonstrated.

## Keywords draft

cricket,fixtures,league,tournament,teams,players,schedule,scorebook,offline

## Privacy labels draft

- **Data Used to Track You:** No
- **Data Linked to You:** No
- **Data Not Linked to You:** No
- **Data Collected:** **None**

Rationale: the app stores user-entered cricket data locally, has no account,
analytics, advertising, or network transport, and embeds `PrivacyInfo.xcprivacy`
with an empty `NSPrivacyCollectedDataTypes` array. A human must re-audit the
exact release build and App Store Connect questionnaire before submission.
Required-reason API declarations are not the same as collected-data labels.

## Support and review fields

- **Support URL:** **PENDING owner-provided public URL**
- **Marketing URL:** Optional; **PENDING**
- **Privacy Policy URL:** **PENDING owner/legal decision and public URL**
- **Copyright:** **PENDING**
- **App Review contact:** **PENDING**
- **Review notes:** Explain that all app data is local, fixture notifications
  are local-only and optional, and no login is required.

## Screenshot plan

Every image below is **PENDING** and must come from a real simulator/device run
of the exact TestFlight version/build. Do not use SwiftUI previews, mockups, or
images from another commit as release evidence.

| Slot | Required scene | Evidence caption |
| --- | --- | --- |
| 1 | Leagues/tournaments list with realistic non-trademarked sample data | Create local leagues and tournaments |
| 2 | Teams and players setup | Keep teams and player roles organized |
| 3 | Fixture editor with ground/date/time | Schedule the next match day |
| 4 | Fixture list with team colors | See upcoming fixtures at a glance |
| 5 | Conflict warning or local reminder option | Catch scheduling conflicts before match day |

Capture all device sizes currently required by App Store Connect, with status
bar content reviewed, no personal data, no third-party trademarks, and no
debug overlays. Record the simulator model, OS version, app version/build,
commit, and source workflow run beside the exported images.
