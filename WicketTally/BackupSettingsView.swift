import OSLog
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WicketStore

struct BackupSettingsView: View {
  let store: WicketStore
  let onDataChanged: (() -> Void)?

  @State private var sharedFile: SharedFile?
  @State private var isImporting = false
  @State private var pendingRestore: PendingRestore?
  @State private var wipePreview: WicketWipePreview?
  @State private var wipeConfirmation = ""
  @State private var message: UserMessage?

  init(store: WicketStore, onDataChanged: (() -> Void)? = nil) {
    self.store = store
    self.onDataChanged = onDataChanged
  }

  var body: some View {
    List {
      Section("Backup and restore") {
        Button("Share full JSON backup", systemImage: "square.and.arrow.up") {
          run {
            sharedFile = try makeSharedFile(
              data: store.makeBackup(),
              filename: "wicket-tally-backup.json"
            )
          }
        }

        Button("Restore from JSON backup", systemImage: "square.and.arrow.down") {
          isImporting = true
        }

        Text(
          "Restore always previews record counts and replaces local data only after confirmation."
        )
        .font(.footnote)
        .indicaSecondaryText()
      }

      .indicaRowBackground()
      Section("CSV files") {
        ForEach(WicketCSVDocument.allCases, id: \.self) { document in
          Button(document.label, systemImage: "doc.text") {
            run {
              sharedFile = try makeSharedFile(
                data: store.makeCSV(document),
                filename: document.filename
              )
            }
          }
        }

        Text(
          "CSV sections use plain headers, one record per line, and quoted commas so pasted text remains readable in messaging apps."
        )
        .font(.footnote)
        .indicaSecondaryText()
      }

      .indicaRowBackground()
      Section("Delete local data") {
        Button("Wipe all data", systemImage: "trash", role: .destructive) {
          run {
            wipePreview = try store.previewWipeAll()
            wipeConfirmation = ""
          }
        }

        Text(
          "Archiving and per-league deletion remain available in Setup. Archiving hides records; it does not delete them."
        )
        .font(.footnote)
        .indicaSecondaryText()
      }
      .indicaRowBackground()
    }
    .indicaScreenBackground()
    .indicaPrimaryText()
    .navigationTitle("Backup & Data")
    .sheet(
      item: $sharedFile,
      onDismiss: {
        do {
          try SharedTemporaryFiles.removeAll()
        } catch {
          message = UserMessage(
            title: "Shared file cleanup failed",
            detail: "A temporary export could not be removed: \(error.localizedDescription)"
          )
        }
      }
    ) { file in
      SystemShareSheet(fileURL: file.url)
    }
    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
      do {
        let url = try result.get()
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
          if didAccess {
            url.stopAccessingSecurityScopedResource()
          }
        }
        let data = try Data(contentsOf: url)
        pendingRestore = PendingRestore(data: data, preview: try store.previewRestore(from: data))
      } catch {
        message = UserMessage(
          title: "Backup could not be opened", detail: error.localizedDescription)
      }
    }
    .alert(
      "Replace local data?",
      isPresented: Binding(
        get: { pendingRestore != nil },
        set: { if !$0 { pendingRestore = nil } }
      ),
      presenting: pendingRestore
    ) { pending in
      Button("Replace local data", role: .destructive) {
        run {
          try store.restoreBackup(from: pending.data, confirming: pending.preview)
          onDataChanged?()
          pendingRestore = nil
          message = UserMessage(
            title: "Restore complete", detail: "The backup replaced local data.")
        }
      }
      Button("Cancel", role: .cancel) {
        pendingRestore = nil
      }
    } message: { pending in
      Text(pending.preview.restoreSummary)
    }
    .sheet(
      isPresented: Binding(
        get: { wipePreview != nil },
        set: { if !$0 { wipePreview = nil } }
      )
    ) {
      NavigationStack {
        Form {
          Section {
            Text(wipePreview?.wipeSummary ?? "")
          } footer: {
            Text(
              "This cannot be undone. Type \(WicketWipePreview.requiredConfirmation) to continue.")
          }
          .indicaRowBackground()

          TextField(WicketWipePreview.requiredConfirmation, text: $wipeConfirmation)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .indicaRowBackground()
        }
        .indicaScreenBackground()
        .indicaPrimaryText()
        .navigationTitle("Wipe all data?")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { wipePreview = nil }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Wipe", role: .destructive) {
              run {
                guard let wipePreview else { return }
                try SharedTemporaryFiles.removeAll()
                try store.wipeAll(
                  typedConfirmation: wipeConfirmation,
                  confirming: wipePreview
                )
                onDataChanged?()
                self.wipePreview = nil
                message = UserMessage(
                  title: "Local data erased", detail: "All user records were deleted.")
              }
            }
            .disabled(wipeConfirmation != WicketWipePreview.requiredConfirmation)
          }
        }
      }
      .presentationDetents([.medium])
    }
    .alert(item: $message) { message in
      Alert(
        title: Text(message.title),
        message: Text(message.detail),
        dismissButton: .default(Text("OK"))
      )
    }
  }

  private func run(_ action: () throws -> Void) {
    do {
      try action()
    } catch {
      message = UserMessage(title: "Local data was not changed", detail: error.localizedDescription)
    }
  }

  private func makeSharedFile(data: Data, filename: String) throws -> SharedFile {
    try SharedTemporaryFiles.removeAll()
    let directory = SharedTemporaryFiles.rootURL
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(filename)
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      let writeError = error
      do {
        try SharedTemporaryFiles.removeDirectory(containing: url)
      } catch {
        SharedTemporaryFiles.logger.error(
          "Failed to clean up an incomplete temporary export: \(error.localizedDescription, privacy: .private)"
        )
      }
      throw writeError
    }
    return SharedFile(url: url)
  }

}

private struct SharedFile: Identifiable {
  let url: URL
  var id: URL { url }
}

private struct SystemShareSheet: UIViewControllerRepresentable {
  let fileURL: URL

  func makeCoordinator() -> Coordinator {
    Coordinator(fileURL: fileURL)
  }

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(
      activityItems: [fileURL],
      applicationActivities: nil
    )
    controller.completionWithItemsHandler = { _, _, _, _ in
      do {
        try SharedTemporaryFiles.removeDirectory(containing: fileURL)
      } catch {
        SharedTemporaryFiles.logger.error(
          "Failed to clean up a temporary export after sharing: \(error.localizedDescription, privacy: .private)"
        )
      }
    }
    return controller
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

  static func dismantleUIViewController(
    _ controller: UIActivityViewController,
    coordinator: Coordinator
  ) {
    do {
      try SharedTemporaryFiles.removeDirectory(containing: coordinator.fileURL)
    } catch {
      SharedTemporaryFiles.logger.error(
        "Failed to clean up a temporary export when dismissing the share sheet: \(error.localizedDescription, privacy: .private)"
      )
    }
  }

  final class Coordinator {
    let fileURL: URL

    init(fileURL: URL) {
      self.fileURL = fileURL
    }
  }
}

private enum SharedTemporaryFiles {
  static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "WicketTally",
    category: "BackupTemporaryFiles"
  )

  static let rootURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("WicketTallyShare", isDirectory: true)

  static func removeDirectory(containing fileURL: URL) throws {
    try remove(fileURL.deletingLastPathComponent())
  }

  static func removeAll() throws {
    try remove(rootURL)
  }

  private static func remove(_ url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
      try FileManager.default.removeItem(at: url)
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
      return
    } catch {
      logger.error(
        "Failed to remove temporary exports at \(url.path, privacy: .private): \(error.localizedDescription, privacy: .private)"
      )
      throw error
    }
  }
}

private struct PendingRestore {
  let data: Data
  let preview: WicketBackupPreview
}

private struct UserMessage: Identifiable {
  let id = UUID()
  let title: String
  let detail: String
}

extension WicketCSVDocument {
  fileprivate var label: String {
    switch self {
    case .scorecards: "Share scorecards CSV"
    case .standings: "Share standings CSV"
    case .playerStats: "Share player stats CSV"
    }
  }
}

extension WicketBackupPreview {
  fileprivate var restoreSummary: String {
    """
    Backup version \(formatVersion) contains \(leagueCount) leagues, \(teamCount) teams, \
    \(playerCount) players, \(fixtureCount) fixtures, and \(totalRecordCount) total database records.
    """
  }
}

extension WicketWipePreview {
  fileprivate var wipeSummary: String {
    "This will permanently delete \(totalRecordCount) records from this device."
  }
}
