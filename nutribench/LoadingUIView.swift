//
//  LoadingUIView.swift
//  nutribench
//
//  Created by Naveen Mysore on 10/24/25.
//

import SwiftUI

struct LoadingUIView: View {
    @State private var sway = false   // drives the leaf wiggle
    
    var body: some View {
        ZStack {
            // Left leaf
            Image("leaf")
                .resizable()
                .frame(width: 48, height: 48)
                .offset(x: 20, y: -45)
                .rotationEffect(.degrees(sway ? 4 : 0), anchor: .bottomLeading)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: sway)

            // Fruit
            Image("fruit")
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(radius: 6, y: 3)
                .rotationEffect(.degrees(sway ? 5 : 0))
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: sway)

        }
        .onAppear { sway = true }
        .accessibilityLabel("Loading")
    }
}

#Preview {
    LoadingUIView()
}
