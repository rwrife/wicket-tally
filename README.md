# Wicket Tally 🏏

**Wicket Tally** is a local-first iPhone app for scheduling and scoring cricket matches — designed first for the sunny village ground and the weekend gully league. Huge sun-proof controls, glanceable scores from across the pitch, and a bold Indian street-cricket look. No accounts, no cloud, no subscriptions.

> Native iPhone app with local scoring, fixtures, statistics, backup controls, and an Indica appearance system. The release candidate and outdoor usability checks still require Apple-runner and human evidence — see Current status.

## Overview

One-sentence pitch: Local-first iPhone cricket match scheduler and ball-by-ball scorer built for outdoor use — oversized sun-legible controls, offline standings and player stats, and an Indian street-cricket visual identity — with no accounts and no cloud.

## Motivation

Cricket at the grassroots level — office teams, gully leagues, weekend tournaments, family and neighbourhood fixtures — is run on WhatsApp groups, paper scorebooks, and shared spreadsheet apps that are unreadable in direct sunlight. Serious scoring apps are built for professional first-class cricket: dense tables, network accounts, and tiny controls meant for a scorer at a desk, not a volunteer standing in the sun holding a phone with sweaty or gloved hands. Meanwhile casual formats (gully cricket, tennis-ball leagues, quick T10/T20 at the ground) have rules paper scorebooks handle but apps ignore.

Wicket Tally puts the whole match day on one offline iPhone: fixtures, teams, toss, ball-by-ball scoring for standard and casual (gully) rule sets, live scorecard legible at arm's length in bright sun, standings, and player stats — wrapped in a design language inspired by Indian street cricket: saturated team-colour kits, hand-painted banner energy, and trophy-glow scoreboards.

## Target users

- Weekend gully / tennis-ball league organizers and scorers in India and the diaspora.
- Office, club, and neighbourhood team managers who set up fixtures and need standings.
- Family and friends running tournaments (weekend 5-a-side through full T20).
- Anyone who scores with a paper book but wants live scorecards, stats, and standings for free.

## Concrete use cases

1. **Fix a match day.** Create a league or one-off tournament, add teams with colours, schedule fixtures on dates and grounds with time slots; the app warns about player/venue double-bookings locally.
2. **Score from the boundary rope.** At the toss, pick the innings; during play, the scorer taps oversized buttons (1, 2, 3, 4, 6, wide, no-ball, bye, leg-bye, wicket type, over complete) sized for sunlight and one-thumb use; a scoreboard glance-mode is readable at arm's length outdoors.
3. **Casual rules without a rulebook.** Enable gully rules: one-hand catch = out, boundary rope marked by chappals, over = 6 balls or N runs, short innings limits — configured once per league, never a legal verdict.
4. **Standings and stats at the tea break.** Points tables (win/tie/NRR-safe manual points), per-player batting/bowling averages, strike rates, economy — computed offline from the ledger.
5. **End of season.** Export the full league history as JSON/CSV backup, share a printable scorecard PDF or plain-text summary the team actually reads on WhatsApp.

## How to use (intended end-to-end workflow)

1. Create a league → add teams (name, colour, players) → schedule fixtures (date, time, ground).
2. On match day open the fixture → record toss and playing XI → start innings.
3. Score ball-by-ball in the outdoor scorer; glance mode shows runs/wickets/overs/RRR/last-over dots.
4. Innings end → auto scorecard → second innings → result auto-derived, editable with a logged manual correction.
5. Standings update instantly; player stats accrue across the league.
6. Back up / export from Settings; restore from a user-picked file. Everything stays on-device until you export it.

## MVP feature list

- Leagues, tournaments, teams, players, and fixtures with grounds and time slots.
- Match-day flow: toss, innings, ball-by-ball scoring with undo/redo and per-over narrative.
- Standard limited-overs rules (T10/T20/ODI length configurable) plus a gully/casual rule preset (user-owned settings, no umpiring advice).
- Outdoor-first UI: high-contrast sunlight themes, ≥ 60 pt primary tap targets, glanceable scoreboard mode, Dark Mode and VoiceOver support, one-handed layout.
- Indian-flair design system: saturated street-cricket palette, jersey-style team colour chips, banner-style match headers, festive tournament moments (e.g. Diwali/IPL-season skins) — tasteful, documented, and skinnable.
- Standings with manual-points safety net; player batting/bowling cards derived from the event ledger.
- Local data: append-only event ledger, deterministic derivations, versioned JSON backup + CSV export, print/share scorecards.
- iPhone Duo design target (future): score surface + live scoreboard split across the dual screen — documented migration path only.

## Non-goals

- No accounts, sign-in, cloud sync, social feed, live streaming, or push between users; zero network by construction.
- No cross-platform frameworks: no Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, or equivalents — native Swift only.
- No Android and no native iPad build (iPhone-only; iPad requires explicit user opt-in).
- No ball-tracking, ball-by-ball video, AI highlights, player-identification, or betting/odds features of any kind.
- No umpiring or DRS-style decision-making; the scorer is the user, corrections are logged facts. No weather, AQI, or playability safety verdicts.
- No franchise/league trademarks, real team names, or official data imports.

## Privacy, permissions, and data storage

All data lives in a local SQLite database on the device. No network calls, accounts, analytics, or ad SDKs are used — enforced by a zero-network CI gate. Notifications are local-only fixture reminders (optional), and Camera/Photo access is never requested.

Users can create a versioned JSON backup of the whole database or line-oriented CSV exports for scorecards, standings, and player stats. Export is always user-initiated through the system Files/share interface; Wicket Tally never uploads exported data. Restore reads a user-picked JSON file, previews its league/team/player/fixture and total record counts, and replaces local records only after explicit confirmation in one atomic database transaction. Cancelling the preview changes nothing.

Archiving only hides a record and does not delete it. Existing per-league deletion shows its cascade preview before removing that league and its children. Wiping all user data requires the exact typed confirmation `DELETE ALL DATA`; database schema and migration metadata remain so the app can immediately create fresh records. Team/player names and other exported content are user-entered data, so users should choose their share destination accordingly.

## Current status and milestones

The app has an iPhone-only SwiftUI target (`com.infinityball.wickettally`), local fixtures and team setup, persisted match ledgers with correction-aware scoring, gully presets, derived standings and scorecards, JSON backup/restore, CSV exports, and skinnable Indica themes. The scoring layout and direct-sunlight appearance still need human field verification and simulator UI-test evidence. Signed TestFlight delivery is pending a run on the exact pinned Xcode with App Store Connect credentials; no TestFlight build has been claimed.

1. M1: Domain core (`WicketKit`) + store + CI skeleton — implemented; pinned Apple-runner evidence pending
2. M2: League/team/fixture setup — implemented
3. M3: Outdoor ball-by-ball scorer + glance mode — implemented; field and UI checks pending
4. M4: Standings, stats, and export — implemented; CI evidence pending
5. M5: Indica themes and TestFlight — themes implemented; human visual audit and signed upload pending

## Development / build quickstart

- Native Swift (SwiftUI) iPhone-only app, iOS 26 SDK, Swift 6, per `toolchain.json` (Xcode 26.0.1 / build 17A400 / iOS SDK 26.0). A missing exact pin on a CI runner is an environment acceptance blocker, never a silent substitute.
- `TARGETED_DEVICE_FAMILY = 1` in every app-target build configuration (project-level and target-level, Debug and Release); CI asserts it pre-build (grep) and post-build (`UIDeviceFamily == [1]` in the built `Info.plist`).
- Bundle id `com.infinityball.wickettally` (registered in App Store Connect); CI enforces the `com.infinityball.` prefix.
- Open `WicketTally.xcodeproj` in the pinned Xcode and build the `WicketTally` scheme for an iPhone simulator, or run the domain/store tests headlessly with `swift test --package-path Packages/WicketKit` (needs system SQLite headers on Linux, e.g. `libsqlite3-dev`).
- CI policy gates: `scripts/check_zero_network.sh` (empty allowlist), `scripts/check_platform_policy.sh` (native iPhone-only bundle policy), and `scripts/check_indica_tokens.sh` (feature-view theme tokens). Run `swift test --package-path Packages/IndicaTheme` to audit theme contrast.
- Signing material (`*.p8`, `*.p12`, `*.mobileprovision`) is gitignored; CI asserts this with `git check-ignore`. Release candidate steps and the manual TestFlight evidence gate are in `docs/release/`; the workflow uses the secret names `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, and `ASC_TEAM_ID` without storing their values.

## License

MIT — see LICENSE.
