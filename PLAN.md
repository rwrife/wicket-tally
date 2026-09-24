# Wicket Tally — PLAN

## Scope

A local-first, offline iPhone app to (1) schedule cricket leagues/matches and (2) score matches ball-by-ball outdoors, with standings, player stats, and exports. Core stance: outdoor ergonomics and sun-legibility before feature breadth; Indian street-cricket visual identity as a first-class design system, not decoration.

### Out of scope (explicit non-goals)

- No accounts, no cloud sync, no backend, no analytics, no ads, no network at all.
- No cross-platform or hybrid frameworks: no Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, or equivalents.
- No Android target and no native iPad support (TARGETED_DEVICE_FAMILY = 1; iPad only by explicit user opt-in).
- No umpiring/DRS decision features, no betting/odds, no player-identity or video features, no official/trademarked league data.
- No weather/AQI playability safety verdicts.

## Architecture

```
WicketTallyApp (SwiftUI, iOS 26+)
  └── Feature views (Setup | Fixtures | Scorer | Standings/Stats | Settings/Export)
        └── WicketKit (pure Swift package — no UI, no GRDB, no Foundation-heavy I/O)
              ├── MatchEvent ledger (append-only; balls, extras, wickets, innings/match lifecycle, logged corrections)
              ├── Rules engine (limited-overs standard + user-configured gully/casual presets)
              ├── Derivations (score, overs/RRR, scorecard, standings points/NRR-safe, player cards) — unknown-safe
              └── Backup codec (versioned JSON; CSV exporters)
        └── WicketStore (GRDB, versioned migrations, fixtures DB)
DesignSystem (Swift package or in-app module)
  ├── SunlightLegible theme tokens (≥ 4.5:1 contrast, high-brightness palettes, ≥ 60 pt tap targets)
  ├── Indica design tokens — Indian street-cricket flair: saturated team-colour kits, hand-painted banner headers,
  │   cricket-ball red + saffron/green accent set, trophy-glow scoreboard, festive seasonal skins
  └── GlanceScoreboard component (arm's-length outdoor legibility)
```

Data model: append-only MatchEvent ledger is the source of truth; every displayed number (runs, wickets, RRR, averages, standings) is a deterministic derivation, never stored mutable state. Corrections are appended events with provenance, preserving recompute integrity.

## Technology choices

- **Swift + SwiftUI, iOS 26 SDK, Swift 6 language mode** — user policy: native Swift only, iPhone-only; pins enforced in `toolchain.json` and CI.
- **Pure-Swift `WicketKit` package** — scoring math is the riskiest correctness surface; isolating it enables exhaustive unit tests (over completion, extras, fallback boundaries) without a simulator.
- **GRDB (SQLite)** — same proven pattern as sibling tool-lab apps; relational queries for standings/stats; versioned migrations; fixture DB for tests.
- **No networking stack at all** — privacy-first by construction; a CI grep gate asserts no URLSession/Network.framework usage in app targets.
- **XCTest** (unit) + snapshot-style layout tests for sun themes; device/simulator evidence reserved for Apple CI when the skeleton lands.

## Milestones & dependency order

1. **M1 — Skeleton + domain core** (issue #1, #2): repo skeleton, CI, toolchain pins enforced, WicketKit ledger + rules engine + derivations green.
2. **M2 — Setup & scheduling** (issues #3, #4): leagues/teams/players CRUD, fixture scheduling with conflict warnings, local reminders.
3. **M3 — Scorer** (issues #5, #6): ball-by-ball UI, undo/redo, over narrative, glance mode, toss→result flow incl. gully presets.
4. **M4 — Outputs** (issues #7, #8): scorecards, standings, player stat cards; backup/export/restore with previewed replace.
5. **M5 — Outdoor & identity polish + release** (issues #9, #10): sun-theme contrast audit, haptics/one-hand ergonomics pass, Indica skin system, accessibility; TestFlight/App Store path with real evidence.

## Testing strategy

- WicketKit: table-driven tests for every rule branch (runs/wickets/extras per ball, over boundaries, innings end, result logic, standings points, NRR-safe manual points, gully presets), property tests for ledger replay == stored expectations, correction-after-recompute invariants.
- Store: migration up/down over fixture DB, backup codec round-trip (version N → N+1), unknown-safe rendering.
- UI: layout tests at smallest iPhone in sun theme (tap target ≥ 60 pt), Dynamic Type max sizes, VoiceOver label pass; no visual-regression claims without Apple-runner screenshots.
- CI gate: zero-network grep, TARGETED_DEVICE_FAMILY=1 assertion, bundle-id prefix assertion.

## Packaging / distribution

Ad-hoc/simulator builds on CI until signing gates pass; then TestFlight via App Store Connect API Actions secrets (names only: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, ASC_TEAM_ID), bundle id `com.infinityball.wickettally` (already registered). App Store release only after real build/archive evidence — never claimed from Linux source checks.

## Risks

- **Rule completeness** — cricket rules are long-tailed; mitigated by append-only ledger + logged manual corrections so any edge case is recoverable rather than corrupting.
- **Outdoor legibility** — untestable on Linux CI; deferred to Apple-runner screenshots + human field check before claiming "sun-proof".
- **Design-system scope creep** — festive skins are skinnable tokens behind one theme protocol, never forked layouts.
- **Gully-rule disputes** — presets are user-owned configuration; app states results as recorded facts, never umpiring advice.
- **Ergonomics under gloves/sweat** — validated by on-device testing (haptics, hit-slop) in M5; flagged as human-verification gate.
