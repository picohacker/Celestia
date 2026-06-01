//
//  CircularProgressBar.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

struct CircularProgressBar: View {
    var progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, min(1.0, progress)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            Text(progressText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
        }
    }
    
    private var progressText: String {
        if progress >= 0.995 {
            return "100%"
        }
        return String(format: "%.0f%%", min(max(progress, 0.0), 1.0) * 100)
    }
}
