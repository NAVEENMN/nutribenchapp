//
//  ContentView.swift
//  nutribench
//
//  Created by Naveen Mysore on 10/1/25.
//

import SwiftUI

enum Tab: Hashable {
    case upload      // Page 1
    case logFood     // Page 2
    case trends      // Page 3
    case photos
}

struct ContentView: View {
    @State private var selection: Tab = .upload
    
    var body: some View {
        TabView(selection: $selection) {
            
            // --- Upload / Health page ---
            Page1View()
                .tabItem {
                    Image(systemName: "doc.text.magnifyingglass")
                        .renderingMode(.template)
                    Text("Indicators")
                }
                .tag(Tab.upload)

            // --- Food logging page ---
            Page2View()
                .tabItem {
                    Image(systemName: "fork.knife.circle.fill")
                        .renderingMode(.template)
                    Text("Log Food")
                }
                .tag(Tab.logFood)
            
            // --- Food Photos page ---
            FoodPhotosView()
                .tabItem {
                    Image(systemName: "square.grid.3x3.fill")
                    Text("Food Photos")
                }
                .tag(Tab.photos)
            
            // --- Glucose trends page ---
            Page3View()
                .tabItem {
                    Image(systemName: "chart.xyaxis.line")
                        .renderingMode(.template)
                    Text("Glucose Trends")
                }
                .tag(Tab.trends)
        }
        // iOS 14 uses .accentColor instead of .tint
        .accentColor(.blue)
    }
}

// Classic previews (works down to iOS 14 toolchains)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
