//
//  SubjectsListItem.swift
//  eda
//
//  Created by Siddhartha Srivastava on 12/07/25.
//

import SwiftUI

struct SubjectsListItem: View {
    var subject: Subject
    var body: some View {
        HStack(alignment: .center) {
            Image(systemName: subject.subjectIcon ?? "network")
                .foregroundStyle(Color("a\(subject.subjectColor ?? "Blue")"))
                .padding()
            Text(subject.subjectName ?? "Untitled Subject").font(.headline)
            Spacer()
        }
        
    }
}
//
//#Preview {
//    SubjectsListItem()
//}
