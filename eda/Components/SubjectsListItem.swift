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
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color("a\(subject.subjectColor ?? "Blue")"))
                .frame(width: 20, height:20)
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
