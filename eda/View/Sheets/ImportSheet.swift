//
//  ImportSheet.swift
//  eda
//
//  Created by Siddhartha Srivastava on 18/07/25.
//

import CoreData
import SwiftUI

struct ImportSheet: View {
    @StateObject private var masterViewModel = MasterViewModel.shared
    @EnvironmentObject private var semesterViewModel: SemesterViewModel

    @State private var showSubjectFileImporter = false
    @State private var showScheduleFileImporter = false

    @State private var importType: String = ""

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Subject Import Section (Always Visible)
                Section {
                    if let fileName = masterViewModel.selectedSubjectFileName {
                        Text(fileName)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        // Clear opposite selection when picking this type
                        if masterViewModel.selectedScheduleFileName != nil {
                            masterViewModel.clearScheduleSelectedFile()
                        }

                        // If file already selected, clear it first (allows changing selection)
                        if masterViewModel.selectedSubjectFileName != nil {
                            masterViewModel.clearSubjectSelectedFile()
                        } else {
                            // Open file picker for new selection
                            importType = "Subject"
                            showSubjectFileImporter = true
                        }
                    } label: {
                        HStack {
                            Image(
                                systemName: masterViewModel.isImporting
                                    && masterViewModel.currentImportType
                                        == .subjects
                                    ? "arrow.down.circle"
                                    : "books.vertical.fill"
                            )

                            // Dynamic button text based on state
                            if masterViewModel.isImporting
                                && masterViewModel.currentImportType
                                    == .subjects
                            {
                                Text("Importing...")
                            } else if masterViewModel.selectedSubjectFileName
                                != nil
                            {
                                Text("Change Subject File")
                            } else {
                                Text("Select Subject File")
                            }

                            if masterViewModel.isImporting
                                && masterViewModel.currentImportType
                                    == .subjects
                            {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(
                        masterViewModel.isImporting
                            || (masterViewModel.selectedScheduleFileName != nil
                                && masterViewModel.selectedSubjectFileName
                                    == nil)
                    )

                } footer: {
                    if masterViewModel.selectedSubjectFileName != nil {
                        Text(
                            "Subject file selected. Tap 'Import Selected File' to begin import, or 'Change Subject File' to select a different file."
                        )
                    } else if masterViewModel.selectedScheduleFileName != nil {
                        Text(
                            "Schedule file is currently selected. Clear it first to select a subject file."
                        )
                    } else {
                        Text(
                            "Step 1: Select a CSV file containing subject information (Name, Teacher, Color, Icon)."
                        )
                    }
                }

                // MARK: - Schedule Import Section (Always Visible)
                Section {
                    if let fileName = masterViewModel.selectedScheduleFileName {
                        Text(fileName)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        // Clear opposite selection when picking this type
                        if masterViewModel.selectedSubjectFileName != nil {
                            masterViewModel.clearSubjectSelectedFile()
                        }

                        // If file already selected, clear it first (allows changing selection)
                        if masterViewModel.selectedScheduleFileName != nil {
                            masterViewModel.clearScheduleSelectedFile()
                        } else {
                            // Open file picker for new selection
                            importType = "Schedule"
                            showScheduleFileImporter = true
                        }
                    } label: {
                        HStack {
                            Image(
                                systemName: masterViewModel.isImporting
                                    && masterViewModel.currentImportType
                                        == .schedules
                                    ? "arrow.down.circle" : "calendar"
                            )

                            // Dynamic button text based on state
                            if masterViewModel.isImporting
                                && masterViewModel.currentImportType
                                    == .schedules
                            {
                                Text("Importing...")
                            } else if masterViewModel.selectedScheduleFileName
                                != nil
                            {
                                Text("Change Schedule File")
                            } else {
                                Text("Select Schedule File")
                            }

                            if masterViewModel.isImporting
                                && masterViewModel.currentImportType
                                    == .schedules
                            {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(
                        masterViewModel.isImporting
                            || (masterViewModel.selectedSubjectFileName != nil
                                && masterViewModel.selectedScheduleFileName
                                    == nil)
                    )

                } footer: {
                    if masterViewModel.selectedScheduleFileName != nil {
                        Text(
                            "Schedule file selected. Tap 'Import Selected File' to begin import, or 'Change Schedule File' to select a different file."
                        )
                    } else if masterViewModel.selectedSubjectFileName != nil {
                        Text(
                            "Subject file is currently selected. Clear it first to select a schedule file."
                        )
                    } else {
                        Text(
                            "Step 1: Select a CSV file containing schedule information (Subject Name, Day, Start Time, End Time, Location). Note: Subject names must match existing subjects exactly."
                        )
                    }
                }

                // MARK: - Import Progress Section (Only when importing)
                if masterViewModel.isImporting
                    && !masterViewModel.importProgress.isEmpty
                {
                    Section("Import Progress") {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(masterViewModel.importProgress)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Import Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                // MARK: - Import Button (Step 2)
                if masterViewModel.selectedSubjectFileName != nil
                    || masterViewModel.selectedScheduleFileName != nil
                {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                if masterViewModel.selectedScheduleFileName
                                    != nil
                                {
                                    masterViewModel
                                        .importSchedulesFromSelectedFile(
                                            for: semesterViewModel
                                                .selectedSemesterForUser!
                                        )
                                } else if masterViewModel
                                    .selectedSubjectFileName != nil
                                {
                                    masterViewModel
                                        .importSubjectsFromSelectedFile(
                                            for: semesterViewModel
                                                .selectedSemesterForUser!
                                        )
                                }
                            }
                        } label: {
                            if masterViewModel.isImporting {
                                Text("Importing...").bold()
                            } else {
                                Text("Import Selected File").bold()
                            }
                        }
                        .disabled(masterViewModel.isImporting)
                    }
                }

                // MARK: - Close Button
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        // Clear selections when closing if not importing
                        if !masterViewModel.isImporting {
                            masterViewModel.clearSubjectSelectedFile()
                            masterViewModel.clearScheduleSelectedFile()
                        }
                        masterViewModel.presentImportSheet = false
                    } label: {
                        Text(masterViewModel.isImporting ? "Cancel" : "Close")
                    }
                    .disabled(masterViewModel.isImporting)
                }
            }
        }

        .fileImporter(
            isPresented: importType == "Subject"
                ? $showSubjectFileImporter : $showScheduleFileImporter,
            allowedContentTypes: [.commaSeparatedText, .text],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }

                // ✅ Start accessing security-scoped resource immediately
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                // ✅ Read file content immediately while we have access
                do {
                    let csvContent = try String(
                        contentsOf: url,
                        encoding: .utf8
                    )
                    let fileName = url.lastPathComponent

                    // ✅ Pass content and filename instead of URL
                    if importType == "Subject" {
                        masterViewModel.selectSubjectCSVContent(
                            csvContent,
                            fileName: fileName
                        )
                    } else if importType == "Schedule" {
                        masterViewModel.selectScheduleCSVContent(
                            csvContent,
                            fileName: fileName
                        )
                    }

                } catch {
                    masterViewModel.showErrorAlert(
                        title: "File Read Failed",
                        message:
                            "Could not read the selected file: \(error.localizedDescription)"
                    )
                }

            case .failure(let error):
                masterViewModel.showErrorAlert(
                    title: "File Selection Failed",
                    message: error.localizedDescription
                )
            }
        }
    }
}

#Preview {
    ImportSheet()
}
