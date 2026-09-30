import SwiftUI
import WicketKit
import WicketStore

struct ScorerView: View {
    @Environment(\.indicaTheme) private var theme
    @Environment(\.indicaThemeSelection) private var themeSelection
    @State private var model: ScorerViewModel
    let homeName: String
    let awayName: String

    @State private var glanceMode = false
    @State private var tossWinner: TeamID
    @State private var tossDecision: TossDecision = .bat
    @State private var extraKind: ExtraType?
    @State private var showingWicketPicker = false
    @State private var showingPlayers = false
    @State private var showingRuleEditor = false
    @State private var extraRuns = 1
    @State private var batRuns = 0
    @State private var wicketKind: WicketKind = .bowled
    @State private var isOneHandCatch = false
    @State private var strikerID = ""
    @State private var nonStrikerID = ""
    @State private var bowlerID = ""
    @State private var dismissedID = ""
    @State private var fielderID = ""

    private var activeTheme: any IndicaTheme {
        glanceMode ? IndicaSunlightTheme() : theme
    }

    init(fixture: FixtureRecord, homeName: String, awayName: String, store: WicketStore?) {
        _model = State(initialValue: ScorerViewModel(fixture: fixture, store: store))
        self.homeName = homeName
        self.awayName = awayName
        _tossWinner = State(initialValue: fixture.homeTeamID)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                scoreboard
                    .padding(16)
            }

            if glanceMode {
                Button("Return to scorer") {
                    glanceMode = false
                }
                .buttonStyle(SunActionButtonStyle())
                .padding(16)
                .accessibilityIdentifier("scorer.return")
            } else {
                controls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .background(activeTheme.palette.background.color.ignoresSafeArea())
        .foregroundStyle(activeTheme.palette.textPrimary.color)
        // Glance mode is read from across the pitch, so it forces the
        // sunlight skin's 7:1 token contrast instead of a static palette.
        .indicaTheme(glanceMode ? .sunlight : themeSelection)
        .navigationTitle(model.fixture.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if model.activeInnings != nil && !glanceMode {
                    Button("Players") {
                        showingPlayers = true
                    }
                    .accessibilityIdentifier("scorer.players")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(glanceMode ? "Score" : "Glance") {
                    glanceMode.toggle()
                }
                .accessibilityIdentifier("scorer.glanceToggle")
            }
        }
        .sheet(
            isPresented: Binding(
                get: { extraKind != nil },
                set: { if !$0 { extraKind = nil } }
            )
        ) {
            if let extraKind {
                extraSheet(extraKind)
            }
        }
        .sheet(isPresented: $showingWicketPicker) {
            wicketSheet
        }
        .sheet(isPresented: $showingRuleEditor) {
            RulePresetEditor(preset: model.session.rules.preset ?? .standard) { preset in
                try model.chooseRules(preset.rules)
            }
        }
        .sheet(isPresented: $showingPlayers) {
            NavigationStack {
                Form { attributionControls }
                    .indicaScreenBackground()
                    .indicaPrimaryText()
                    .navigationTitle("Player attribution")
                    .toolbar {
                        Button("Done") { showingPlayers = false }
                    }
            }
        }
        .alert(
            "Scoring error",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 10) {
            if model.toss == nil {
                tossControls
            } else if model.state.status == .notStarted || model.isInningsBreak {
                Button(model.isInningsBreak ? "Start second innings" : "Start first innings") {
                    model.startNextInnings()
                }
                .buttonStyle(SunActionButtonStyle())
                .accessibilityIdentifier("scorer.startInnings")
                correctionControls
            } else if model.activeInnings != nil {
                if model.needsOverCompletion {
                    Button("Over complete") {
                        model.completeOver()
                    }
                    .buttonStyle(SunActionButtonStyle())
                    .accessibilityIdentifier("scorer.overComplete")
                } else {
                    runGrid
                    extrasGrid
                    Button("Wicket") {
                        showingWicketPicker = true
                    }
                    .buttonStyle(SunActionButtonStyle(accent: true))
                    .accessibilityIdentifier("scorer.wicket")
                }
                correctionControls
            } else {
                Text("Match complete")
                    .font(.largeTitle.bold())
                correctionControls
            }
        }
    }

    private var runGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(model.session.rules.runPresets, id: \.self) { runs in
                Button("\(runs)") {
                    model.record(
                        BallEvent(
                            striker: player(strikerID),
                            nonStriker: player(nonStrikerID),
                            bowler: player(bowlerID),
                            runsOffBat: runs
                        )
                    )
                }
                .buttonStyle(SunActionButtonStyle())
                .accessibilityLabel("\(runs) runs")
                .accessibilityIdentifier("scorer.ball.\(runs)")
            }
        }
    }

    private var extrasGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
            spacing: 8
        ) {
            extraButton("Wide", kind: .wide)
            extraButton("No ball + runs", kind: .noBall)
            extraButton("Bye", kind: .bye)
            extraButton("Leg bye", kind: .legBye)
        }
    }

    private var correctionControls: some View {
        HStack(spacing: 12) {
            Button("Undo") { model.undo() }
                .disabled(!model.canUndo)
                .accessibilityIdentifier("scorer.undo")

            Spacer()

            if model.activeInnings != nil {
                Button("End innings") { model.endInnings() }
                    .accessibilityIdentifier("scorer.endInnings")
                Spacer()
            }

            Button("Redo") { model.redo() }
                .disabled(!model.canRedo)
                .accessibilityIdentifier("scorer.redo")
        }
        .font(.headline)
        .frame(minHeight: 60)
    }

    private var scoreboard: some View {
        let innings = model.state.innings.last
        return VStack(spacing: glanceMode ? 22 : 10) {
            Text(innings.map { teamName($0.battingTeam) } ?? "Awaiting toss")
                .font(glanceMode ? .title.bold() : .headline)

            Text(innings?.scoreline ?? "0/0")
                .font(.system(size: glanceMode ? 92 : 58, weight: .black, design: .rounded))
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .accessibilityIdentifier("scorer.score")

            HStack {
                Text(
                    "Overs \(innings?.oversString(ballsPerOver: model.session.rules.ballsPerOver) ?? "0.0")"
                )
                Spacer()
                Text("RRR \(rate(model.state.requiredRunRate))")
            }
            .font(glanceMode ? .title2.bold() : .headline)
            .accessibilityIdentifier("scorer.oversRRR")

            RulePresetHeader(rules: model.session.rules)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("scorer.rulesSummary")

            VStack(alignment: .leading, spacing: 6) {
                Text("Last over")
                    .font(.headline)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6),
                    spacing: 4
                ) {
                    ForEach(0..<6, id: \.self) { index in
                        Text(index < model.lastOverDots.count ? model.lastOverDots[index] : "–")
                            .font(glanceMode ? .title2.bold() : .headline.bold())
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: glanceMode ? 60 : 40)
                            .background(
                                activeTheme.palette.background.color,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One explicit label so the strip is a single predictable
            // accessibility element regardless of lazy dot rendering.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lastOverLabel)
            .accessibilityIdentifier("scorer.lastOver")
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(activeTheme.palette.surface.color, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("scorer.scoreboard")
    }

    private var tossControls: some View {
        VStack(spacing: 12) {
            Text("Toss winner")
                .font(.title2.bold())

            Picker("Toss winner", selection: $tossWinner) {
                Text(homeName).tag(model.fixture.homeTeamID)
                Text(awayName).tag(model.fixture.awayTeamID)
            }
            .pickerStyle(.segmented)

            Picker("Decision", selection: $tossDecision) {
                Text("Bat").tag(TossDecision.bat)
                Text("Bowl").tag(TossDecision.bowl)
            }
            .pickerStyle(.segmented)

            Picker(
                "Overs",
                selection: Binding(
                    get: { model.session.rules.oversPerInnings },
                    set: { overs in
                        try? model.chooseRules(MatchRules(oversPerInnings: overs))
                    }
                )
            ) {
                Text("T10").tag(10)
                Text("T20").tag(20)
                Text("ODI").tag(50)
            }
            .pickerStyle(.segmented)

            Button("Custom match rules") {
                showingRuleEditor = true
            }
            .buttonStyle(SunActionButtonStyle(compact: true))
            .accessibilityIdentifier("scorer.customRules")

            Button("Record toss") {
                model.recordToss(winner: tossWinner, decision: tossDecision)
            }
            .buttonStyle(SunActionButtonStyle())
            .accessibilityIdentifier("scorer.recordToss")
        }
    }

    private func extraButton(_ title: String, kind: ExtraType) -> some View {
        Button(title) {
            extraRuns = kind == .wide || kind == .noBall ? 1 : 0
            batRuns = 0
            extraKind = kind
        }
        .buttonStyle(SunActionButtonStyle(compact: true))
        .accessibilityIdentifier("scorer.extra.\(kind.rawValue)")
    }

    private func extraSheet(_ kind: ExtraType) -> some View {
        NavigationStack {
            Form {
                Stepper(
                    "Extra runs: \(extraRuns)",
                    value: $extraRuns,
                    in: (kind == .wide || kind == .noBall ? 1 : 0)...20
                )
                .indicaRowBackground()
                if kind == .noBall {
                    Stepper("Runs off bat: \(batRuns)", value: $batRuns, in: 0...6)
                        .indicaRowBackground()
                }
                attributionControls
                Button("Record \(extraLabel(kind))") {
                    model.record(
                        BallEvent(
                            striker: player(strikerID),
                            nonStriker: player(nonStrikerID),
                            bowler: player(bowlerID),
                            runsOffBat: batRuns,
                            extra: ExtraEvent(kind: kind, runs: extraRuns)
                        )
                    )
                    extraKind = nil
                }
                .frame(minHeight: 60)
                .accessibilityIdentifier("scorer.recordExtra")
                .indicaRowBackground()
            }
            .indicaScreenBackground()
            .indicaPrimaryText()
            .navigationTitle(extraLabel(kind))
            .toolbar {
                Button("Cancel") { extraKind = nil }
            }
        }
    }

    private var wicketSheet: some View {
        NavigationStack {
            Form {
                Picker("Dismissal", selection: $wicketKind) {
                    ForEach(
                        [
                            WicketKind.bowled,
                            .caught,
                            .lbw,
                            .runOut,
                            .stumped,
                            .hitWicket,
                            .retired,
                        ],
                        id: \.self
                    ) { kind in
                        Text(wicketLabel(kind)).tag(kind)
                    }
                }
                .indicaRowBackground()

                Picker("Dismissed batter (optional)", selection: $dismissedID) {
                    Text("Unspecified").tag("")
                    ForEach(model.battingPlayers) {
                        Text($0.name).tag($0.id.rawValue)
                    }
                }
                .indicaRowBackground()

                Picker("Fielder (optional)", selection: $fielderID) {
                    Text("Unspecified").tag("")
                    ForEach(model.bowlingPlayers) {
                        Text($0.name).tag($0.id.rawValue)
                    }
                }
                .indicaRowBackground()

                if wicketKind == .caught && model.session.rules.oneHandCatchAllowed {
                    Toggle("One-hand catch", isOn: $isOneHandCatch)
                        .indicaRowBackground()
                }

                attributionControls

                Button("Record wicket") {
                    let dismissed = player(dismissedID)
                        ?? player(strikerID)
                        ?? PlayerID("unspecified")
                    model.record(
                        BallEvent(
                            striker: player(strikerID),
                            nonStriker: player(nonStrikerID),
                            bowler: player(bowlerID),
                            runsOffBat: 0,
                            wicket: WicketEvent(
                                kind: wicketKind,
                                dismissed: dismissed,
                                fielder: player(fielderID),
                                isOneHandCatch: wicketKind == .caught && isOneHandCatch
                            )
                        )
                    )
                    showingWicketPicker = false
                }
                .frame(minHeight: 60)
                .accessibilityIdentifier("scorer.recordWicket")
                .indicaRowBackground()
            }
            .indicaScreenBackground()
            .indicaPrimaryText()
            .navigationTitle("Wicket")
            .toolbar {
                Button("Cancel") { showingWicketPicker = false }
            }
        }
    }

    private var attributionControls: some View {
        Group {
            Picker("Striker (optional)", selection: $strikerID) {
                Text("Unspecified").tag("")
                ForEach(model.battingPlayers) {
                    Text($0.name).tag($0.id.rawValue)
                }
            }
            .indicaRowBackground()
            Picker("Non-striker (optional)", selection: $nonStrikerID) {
                Text("Unspecified").tag("")
                ForEach(model.battingPlayers) {
                    Text($0.name).tag($0.id.rawValue)
                }
            }
            .indicaRowBackground()
            Picker("Bowler (optional)", selection: $bowlerID) {
                Text("Unspecified").tag("")
                ForEach(model.bowlingPlayers) {
                    Text($0.name).tag($0.id.rawValue)
                }
            }
            .indicaRowBackground()
        }
    }

    private func player(_ rawValue: String) -> PlayerID? {
        rawValue.isEmpty ? nil : PlayerID(rawValue)
    }

    private func teamName(_ id: TeamID) -> String {
        id == model.fixture.homeTeamID ? homeName : awayName
    }

    private func rate(_ value: NumericValue) -> String {
        switch value {
        case let .known(rate): return rate.formatted(.number.precision(.fractionLength(2)))
        case .unknown: return "–"
        }
    }

    /// Stable VoiceOver + UI-test label for the last-over strip. Built
    /// explicitly because the lazy dot grid may render only visible cells.
    private var lastOverLabel: String {
        let dots = model.lastOverDots.isEmpty ? "–" : model.lastOverDots.joined(separator: ", ")
        return "Last over \(dots)"
    }

    private func extraLabel(_ kind: ExtraType) -> String {
        switch kind {
        case .wide: return "wide"
        case .noBall: return "no ball"
        case .bye: return "bye"
        case .legBye: return "leg bye"
        }
    }

    private func wicketLabel(_ kind: WicketKind) -> String {
        switch kind {
        case .bowled: return "Bowled"
        case .caught: return "Caught"
        case .lbw: return "LBW"
        case .runOut: return "Run out"
        case .stumped: return "Stumped"
        case .hitWicket: return "Hit wicket"
        case .retired: return "Retired"
        default: return kind.rawValue
        }
    }
}

/// Outdoor action button. Colour comes only from the active Indica theme, so
/// the sunlight skin's high-contrast tokens apply automatically.
private struct SunActionButtonStyle: ButtonStyle {
    var accent = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        SunActionButtonBody(accent: accent, compact: compact, configuration: configuration)
    }

    private struct SunActionButtonBody: View {
        @Environment(\.indicaTheme) private var theme
        let accent: Bool
        let compact: Bool
        let configuration: ButtonStyle.Configuration

        var body: some View {
            configuration.label
                .font(compact ? .headline.bold() : .title2.bold())
                .frame(maxWidth: .infinity, minHeight: compact ? 60 : 64)
                .foregroundStyle(theme.palette.textOnAccent.color)
                .background(
                    accent ? theme.palette.destructive.color : theme.palette.accentPrimary.color,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        }
    }
}
