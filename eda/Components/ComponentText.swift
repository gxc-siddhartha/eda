//
//  ComponentText.swift
//  eda
//
//  Created by Siddhartha Srivastava on 25/07/25.
//

import SwiftUI

struct ComponentText: View {
    var body: some View {
        HStack(spacing:0) {
            ZStack {
                Rectangle().fill(Color.green.opacity(0.1))
                Image(systemName: "p.circle.fill")
                    .foregroundStyle(Color.green)
            }
            
            ZStack {
                Rectangle().fill(Color.red.opacity(0.1))
                Image(systemName: "a.circle.fill")
                    .foregroundStyle(Color.red)
            }
            
            ZStack {
                Rectangle().fill(Color.accentColor.opacity(0.1))
                Image(systemName: "bandage.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(height:65)
    }
}

#Preview {
    ComponentText()
}
