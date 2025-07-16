//
//  CreateSemesterSheet.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import SwiftUI

struct CreateSemesterSheet: View {
    @EnvironmentObject private var semesterViewModel : SemesterViewModel
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Select Semester", selection: $semesterViewModel.selectedSemesterName) {
                        ForEach(semesterViewModel.semesterOptions, id: \.self) {semester in
                            Text(semester)
                        }
                    
                    }.pickerStyle(.menu).frame(height:22)
                    
                  
                  
                }
                Section("Attendance Requirement") {
                    HStack {
                        Text("Percentage").padding(.trailing)
                        TextField("75", text: $semesterViewModel.passingPercentage)
                    }
                    
                }
                
                Section("Start Date") {
                    DatePicker("Start Date", selection: $semesterViewModel.semesterStartDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                
                Section("End Date") {
                    DatePicker("Start Date", selection: $semesterViewModel.semesterEndDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                
                
            }.navigationTitle(Text("Create Semester")).navigationBarTitleDisplayMode(.inline)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task {
                                if(semesterViewModel.isFormValid) {
                                   _ = try await semesterViewModel.createSemester()
                                }
                            }
                        } label: {
                            Text("Done").bold().disabled(!semesterViewModel.isFormValid)
                        }
                    }
                    
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            semesterViewModel.presentSemesterDetailsSheet = false
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
    CreateSemesterSheet().environmentObject(SemesterViewModel())
}
