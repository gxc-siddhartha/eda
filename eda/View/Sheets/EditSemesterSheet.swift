//
//  CreateSemesterSheet.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import SwiftUI

struct EditSemesterSheet: View {
    @EnvironmentObject private var semesterViewModel : SemesterViewModel
    

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Selected Semester", selection: $semesterViewModel.editSemesterName) {
                        ForEach(semesterViewModel.semesterOptions, id: \.self) {semester in
                            Text(semester)
                        }
                    
                    }.pickerStyle(.menu).frame(height:22)
                        .disabled(true)
                    
                  
                  
                }
                Section("Attendance Requirement") {
                    HStack {
                        Text("Percentage").padding(.trailing)
                        TextField("75", text: $semesterViewModel.editedPassingPercentage)
                    }
                    
                }
                
                Section("Start Date") {
                    DatePicker("Start Date", selection: $semesterViewModel.editSemesterStartDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .disabled(true)
                }
                
                Section("End Date") {
                    DatePicker("Start Date", selection: $semesterViewModel.editedEndDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                
                
            }.navigationTitle(Text("Edit Semester")).navigationBarTitleDisplayMode(.inline)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task {
                                    await semesterViewModel.updateSemester()
                            }
                        } label: {
                            Text("Done").bold()
                        }
                    }
                    
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            semesterViewModel.presentSemesterEditSheet = false
                        } label: {
                            Text("Close")
                        }
                    }
                }
                .alert(isPresented: $semesterViewModel.showErrorAlert, content: {
                    Alert(title: Text(semesterViewModel.alertTitle), message: Text(semesterViewModel.alertMessage), dismissButton: .default(Text("Ok")))
                })
        }
    }
}

#Preview {
    EditSemesterSheet().environmentObject(SemesterViewModel())
}
