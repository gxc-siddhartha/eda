//
//  CreateSemesterSheet.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import SwiftUI

struct CreateSubjectSheet: View {
    @EnvironmentObject var semesterViewModel: SemesterViewModel
    @EnvironmentObject var subjectViewModel: SubjectViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Subject Details") {
                    HStack(spacing: 16, ) {
                        Text("Subject Name").lineLimit(1)
                        TextField(
                            "Mathematics II",
                            text: $subjectViewModel.subjectName
                        ).foregroundStyle(Color.accentColor)
                    }
                    HStack(spacing: 16, ) {
                        Text("Subject Teacher").lineLimit(1)
                        TextField(
                            "John Appleseed",
                            text: $subjectViewModel.subjectTeacher
                        ).foregroundStyle(Color.accentColor)
                    }

                }

                Section("Subject Color") {
                    HStack {

                        Picker(
                            "Select Color",
                            selection: $subjectViewModel.subjectColor
                        ) {
                            ForEach(
                                subjectViewModel.availableColors,
                                id: \.self
                            ) { color in
                                HStack {
                                    Circle().fill(Color("a\(color)")).frame(
                                        width: 15,
                                        height: 15
                                    )
                                    Text(color)

                                }

                            }
                        }.pickerStyle(.navigationLink).frame(height: 22)
                    }
                }

                Section("Subject Icon") {

                    HStack {
                        Image(systemName: subjectViewModel.subjectIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 20)
                            .foregroundStyle(
                                Color("a\(subjectViewModel.subjectColor)")
                            )
                        Picker(
                            "Select Icon",
                            selection: $subjectViewModel.subjectIcon
                        ) {
                            ForEach(subjectViewModel.availableIcons, id: \.self)
                            { icon in
                                Image(systemName: icon)

                            }
                        }.pickerStyle(.navigationLink).frame(height: 22)
                    }

                }
            }.navigationTitle(Text("Create Subject"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task {
                                if subjectViewModel.isFormValid {
                                    _ =
                                        try await subjectViewModel.createSubject(
                                            semester: semesterViewModel
                                                .selectedSemesterForUser
                                        )
                                }
                            }
                        } label: {
                            Text("Done").disabled(!subjectViewModel.isFormValid)
                        }
                    }

                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            subjectViewModel.presentSubjectCreateSheet = false
                            subjectViewModel.clearForm()
                        } label: {
                            Text("Close")
                        }
                    }
                }
            // ✅ ADDED: Missing error alert
                        .alert(isPresented: $subjectViewModel.showErrorAlert) {
                            Alert(
                                title: Text(subjectViewModel.alertTitle),
                                message: Text(subjectViewModel.alertMessage),
                                dismissButton: .default(Text("OK")) {
                                    subjectViewModel.clearAlerts()
                                }
                            )
                        }

            //                .alert(isPresented: $semesterViewModel.showErrorAlert, content: {
            //                    Alert(title: Text(semesterViewModel.alertTitle), message: Text(semesterViewModel.alertMessage), dismissButton: .default(Text("Ok")))
            //                })

        }
    }
}

#Preview {
    CreateSubjectSheet().environmentObject(SubjectViewModel())
        .environmentObject(SemesterViewModel())
}
