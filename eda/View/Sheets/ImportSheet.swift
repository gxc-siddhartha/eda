//
//  ImportSheet.swift
//  eda
//
//  Created by Siddhartha Srivastava on 18/07/25.
//

import SwiftUI
import CoreData

struct ImportSheet: View {
    @StateObject private var masterViewModel = MasterViewModel.shared
    @EnvironmentObject private var semesterViewModel : SemesterViewModel
    
    @State private var showSubjectFileImporter = false
    @State private var showScheduleFileImporter = false
    
    @State private var importType : String = ""
    
    var body: some View {
        NavigationStack {
            List {
                if(masterViewModel.selectedScheduleFileName == nil) {
                    Section {
                        if(masterViewModel.selectedSubjectFileName != nil) {
                            Text(masterViewModel.selectedSubjectFileName!)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            importType = "Subject"
                            showSubjectFileImporter = true
                        } label: {
                            HStack {
                                Image(systemName: masterViewModel.isImporting ? "arrow.down.circle" : "books.vertical.fill")
                                Text(masterViewModel.isImporting ? "Importing..." : "Import Subjects")
                                if masterViewModel.isImporting {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                        }
                        .disabled(masterViewModel.isImporting)
                        
                        
                    } footer: {
                        Text("You can import all of your subjects at once with the help of a .csv file. This file should contain only the subjects' information.")
                    }
                    
                }
                
                if(masterViewModel.selectedSubjectFileName == nil ) {
                    if(masterViewModel.selectedScheduleFileName != nil) {
                        Text(masterViewModel.selectedScheduleFileName!)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        Button {
                            importType = "Schedule"
                            showScheduleFileImporter = true
                        } label: {
                            HStack {
                                Image(systemName: "calendar")
                                Text("Import Schedules")
                            }
                        }
                    } footer: {
                        Text("You can import all of your schedules at once with the help of a .csv file.\nNote the name of the subjects should be exact same.")
                    }
                }
                
            }
            .navigationTitle("Import Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                if(masterViewModel.selectedSubjectFileName != nil || masterViewModel.selectedScheduleFileName != nil) {
                    ToolbarItem(placement: .topBarTrailing) {
                        
                        Button {
                            Task {
                                if(masterViewModel.selectedScheduleFileName != nil) {
                                    masterViewModel.importSchedulesFromSelectedFile(for: semesterViewModel.selectedSemesterForUser!)
                                } else {
                                    masterViewModel.importSubjectsFromSelectedFile(for: semesterViewModel.selectedSemesterForUser!)
                                }
                            }
                        } label: {
                            Text("Done").bold()
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarLeading,) {
                    Button {
                        masterViewModel.presentImportSheet = false
                    } label: {
                        Text("Close")
                    }
                }
                
            }
        }
        
        .fileImporter(
            isPresented: importType == "Subject" ? $showSubjectFileImporter : $showScheduleFileImporter,
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
                    let csvContent = try String(contentsOf: url, encoding: .utf8)
                    let fileName = url.lastPathComponent
                    
                    // ✅ Pass content and filename instead of URL
                    if (importType == "Subject") {
                        masterViewModel.selectSubjectCSVContent(csvContent, fileName: fileName)
                    } else if( importType == "Schedule"){
                        masterViewModel.selectScheduleCSVContent(csvContent, fileName: fileName)
                    }
                    
                } catch {
                    masterViewModel.showErrorAlert(
                        title: "File Read Failed",
                        message: "Could not read the selected file: \(error.localizedDescription)"
                    )
                }
                
            case .failure(let error):
                masterViewModel.showErrorAlert(title: "File Selection Failed", message: error.localizedDescription)
            }
        }
        
    }
}

#Preview {
    ImportSheet()
}
