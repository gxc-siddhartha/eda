//  ManageSemesterSheet.swift
//  eda
//
//  Updated to support editing existing semesters via EditSemesterSheet

import SwiftUI

struct ManageSemesterSheet: View {
    @EnvironmentObject private var semesterViewModel: SemesterViewModel
    @EnvironmentObject private var subjectViewModel: SubjectViewModel
    @EnvironmentObject private var schedulesViewModel: ScheduleViewModel
    @State private var showDeleteAlert: Bool = false
    @State private var semesterToDelete: Semester? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("My Semesters") {
                    ForEach(semesterViewModel.semesterList, id: \.semesterId) {
                        semester in
                        HStack {
                            Text(semester.semesterName ?? "")
                            Spacer()

                            // Delete Button
                            Button {
                                semesterViewModel.startEditing(semester)
                                semesterViewModel.presentSemesterEditSheet =
                                    true
                            } label: {
                                Image(systemName: "pencil").foregroundStyle(
                                    Color.accentColor
                                )
                            }.padding(.trailing)
                                .buttonStyle(.plain)

                            // Delete Button
                            Button {
                                semesterToDelete = semester
                                showDeleteAlert = true
                            } label: {
                                Image(systemName: "trash").foregroundStyle(
                                    Color.red
                                )
                            }.buttonStyle(.plain)
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
            .sheet(isPresented: $semesterViewModel.presentSemesterEditSheet) {
                EditSemesterSheet()
                    .presentationDragIndicator(.visible)

            }

            .alert(isPresented: $showDeleteAlert) {
                let toDelete = semesterToDelete!
                return Alert(
                    title: Text("Delete Semester"),
                    message: Text(
                        " This will remove all subjects and schedules associated with this semester. Are you sure you want to delete this semester?"
                    ),
                    primaryButton: .destructive(Text("Delete")) {
                        Task {
                            try await semesterViewModel.deleteSemester(toDelete)
                            if semesterViewModel.selectedSemesterForUser != nil
                            {
                                try await subjectViewModel.loadSubjects(
                                    semester: semesterViewModel
                                        .selectedSemesterForUser!
                                )
                                schedulesViewModel.selectedDate = Date()
                                try await schedulesViewModel.loadSchedules(
                                    for: Date(),
                                    semester: semesterViewModel
                                        .selectedSemesterForUser!
                                )
                            } else {
                                subjectViewModel.subjectsList.removeAll()
                                schedulesViewModel.schedulesList.removeAll()
                                schedulesViewModel.schedulesForSelectedDate
                                    .removeAll()
                                schedulesViewModel.todaySchedules.removeAll()
                                schedulesViewModel.currentActiveSchedule = nil

                            }
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
