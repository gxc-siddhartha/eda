//
//  MasterViewModel.swift
//  eda
//
//  Created by Siddhartha Srivastava on 16/07/25.
//
import Foundation

class MasterViewModel: ObservableObject {
    static let shared = MasterViewModel()
    
    @Published var showAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    
}
