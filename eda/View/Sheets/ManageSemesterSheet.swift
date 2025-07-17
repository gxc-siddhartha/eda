//  ManageSemesterSheet.swift
//  eda
//
//  Updated to support editing existing semesters via EditSemesterSheet

import SwiftUI

struct ManageSemesterSheet: View {
    @EnvironmentObject private var semesterViewModel: SemesterViewModel
    @State private var showDeleteAlert: Bool = false
    @State private var semesterToDelete: Semester? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("My Semesters") {
                    ForEach(semesterViewModel.semesterList, id: \.semesterId) { semester in
                        HStack {
                            Text(semester.semesterName ?? "")
                            Spacer()
                            
                            // Delete Button
                            Button {
                                semesterToDelete = semester
                                showDeleteAlert = true
                            } label: {
                                Image(systemName: "trash").foregroundStyle(Color.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manage Semesters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        semesterViewModel.presentManageSemestersSheet = false
                    }
                }
            }

            // Delete Confirmation
            .alert(isPresented: $showDeleteAlert) {
                let toDelete = semesterToDelete!
                return Alert(
                    title: Text("Delete Semester"),
                    message: Text("Are you sure you want to delete this semester?"),
                    primaryButton: .destructive(Text("Delete")) {
                        Task {
                            try await semesterViewModel.deleteSemester(toDelete)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
}
//
//#if DEBUG
//struct ManageSemesterSheet_Previews: PreviewProvider {
//    static var previews: some View {
//        ManageSemesterSheet()
//            .environmentObject(SemesterViewModel())
//    }
//}
