import Foundation
import SwiftUI
import WicketKit

/// Draft-only: no database writes or reminder authorization until confirmation.
private struct ProposedFixture: Identifiable {
    let id = UUID()
    let round: Int
    let pairing: SchedulePairing
    var start: Date
    var end: Date
    var groundID: GroundID
}

struct ScheduleDraftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.indicaTheme) private var theme
    let model: FixturesViewModel
    @State private var leagueID: LeagueID?
    @State private var format: ScheduleFormat = .roundRobin
    @State private var plan: SchedulePlan?
    @State private var slots: [ProposedFixture] = []
    @State private var start = Date().addingTimeInterval(86_400)
    @State private var confirmation: (records: [FixtureRecord], conflicts: [[FixtureConflict]])?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Tournament", selection: $leagueID) {
                    ForEach(model.leagues) { league in
                        Text(league.name).tag(Optional(league.id))
                    }
                }
                .indicaRowBackground()
                Picker("Format", selection: $format) {
                    ForEach(ScheduleFormat.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .indicaRowBackground()
                DatePicker("First match", selection: $start)
                    .indicaRowBackground()
                Button("Generate draft") { generate() }
                    .frame(minHeight: 60)
                    .disabled(leagueID == nil || model.grounds.isEmpty)
                    .indicaRowBackground()

                if let plan {
                    Section("Review — \(plan.rounds.count) rounds, \(plan.projectedMatchCount) projected matches") {
                        Text("Choose match-day players in each fixture editor after saving. \(plan.knownMatchCount) pairings can be scheduled now. Future knockout matches with undecided winners remain unscheduled until teams are known.")
                            .font(.subheadline)
                            .foregroundStyle(theme.palette.textSecondary.color)
                        ForEach(plan.rounds, id: \.number) { round in
                            Text("Round \(round.number)").font(.headline)
                            ForEach(round.pairings.indices, id: \.self) { index in
                                let pair = round.pairings[index]
                                if !pair.isPlayable {
                                    Text(pair.home == nil && pair.away == nil ? "Winners to be determined" : "Bye: \(name(pair.home ?? pair.away))")
                                        .foregroundStyle(theme.palette.textSecondary.color)
                                }
                            }
                        }
                    }
                    .indicaRowBackground()
                    Section("Proposed fixtures — edit each time and ground") {
                        ForEach(slots.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Round \(slots[index].round) · \(name(slots[index].pairing.home)) vs \(name(slots[index].pairing.away))")
                                    .font(.headline)
                                DatePicker("Starts", selection: $slots[index].start)
                                DatePicker("Ends", selection: $slots[index].end)
                                Picker("Ground", selection: $slots[index].groundID) {
                                    ForEach(model.grounds) { ground in
                                        Text(ground.name).tag(ground.id)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .indicaRowBackground()
                    Button("Review and save \(slots.count) fixtures") { review() }
                        .frame(minHeight: 60)
                        .indicaRowBackground()
                }
            }
            .indicaScreenBackground()
            .indicaPrimaryText()
            .navigationTitle("Schedule draft")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { leagueID = leagueID ?? model.leagues.first?.id }
            .onChange(of: leagueID) { _, _ in plan = nil; slots = [] }
            .onChange(of: format) { _, _ in plan = nil; slots = [] }
            .alert("Confirm tournament fixtures", isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            )) {
                Button("Cancel", role: .cancel) { confirmation = nil }
                Button("Save fixtures") { commit() }
            } message: {
                let warnings = confirmation?.conflicts.flatMap { $0 }.map(\.explanation) ?? []
                Text("Save \(confirmation?.records.count ?? 0) fixtures atomically? \(warnings.isEmpty ? "No ground or player overlap warnings." : warnings.joined(separator: "\n")) Existing fixtures and scorecards will not be changed.")
            }
            .alert("Schedule unavailable", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) { Button("OK", role: .cancel) { error = nil } } message: { Text(error ?? "") }
        }
    }

    private func name(_ id: TeamID?) -> String {
        guard let id else { return "TBD" }
        return model.team(id)?.name ?? "Unavailable team"
    }

    private func generate() {
        guard let leagueID, let ground = model.grounds.first else { return }
        do {
            let teams = model.teams.filter { $0.leagueID == leagueID }.map(\.id)
            let draft = try ScheduleGenerator.generate(teams: teams, format: format)
            plan = draft
            slots = draft.rounds.flatMap { round in
                round.pairings.enumerated().compactMap { index, pairing in
                    guard pairing.isPlayable else { return nil }
                    let offset = TimeInterval((round.number - 1) * 7 + index) * 86_400
                    return ProposedFixture(round: round.number, pairing: pairing,
                        start: start.addingTimeInterval(offset),
                        end: start.addingTimeInterval(offset + 7_200), groundID: ground.id)
                }
            }
        } catch { self.error = "Add at least two distinct teams to this tournament before generating a schedule." }
    }

    private func review() {
        guard let leagueID else { return }
        do {
            let now = Date(timeIntervalSince1970: Double(Int64(Date().timeIntervalSince1970 * 1000)) / 1000)
            let records = try slots.map { slot -> FixtureRecord in
                guard let home = slot.pairing.home, let away = slot.pairing.away else { throw ScheduleError.notEnoughTeams }
                return try FixtureRecord.validated(
                    id: FixtureID(UUID().uuidString.lowercased()), leagueID: leagueID,
                    name: "Round \(slot.round): \(name(home)) vs \(name(away))",
                    homeTeamID: home, awayTeamID: away, groundID: slot.groundID,
                    participatingPlayerIDs: [],
                    startsAt: Date(timeIntervalSince1970: Double(Int64(slot.start.timeIntervalSince1970 * 1000)) / 1000),
                    endsAt: Date(timeIntervalSince1970: Double(Int64(slot.end.timeIntervalSince1970 * 1000)) / 1000),
                    reminder: .none, createdAt: now, updatedAt: now
                )
            }
            confirmation = (records, try model.previewSchedule(records))
        } catch { self.error = "Review fixture times and grounds before saving: \(error.localizedDescription)" }
    }

    private func commit() {
        guard let confirmation else { return }
        do {
            try model.commitSchedule(confirmation.records, confirmedConflicts: confirmation.conflicts)
            dismiss()
        } catch { self.error = "Schedule changed or could not be saved. Regenerate and review it before trying again: \(error.localizedDescription)" }
        self.confirmation = nil
    }
}
