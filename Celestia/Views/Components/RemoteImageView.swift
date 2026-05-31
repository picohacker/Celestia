//
//  RemoteImageView.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI
import Kingfisher

struct RemoteImageView: View {
    let url: URL?
    let cornerRadius: CGFloat
    
    init(url: URL?, cornerRadius: CGFloat = 8) {
        self.url = url
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        KFImage(url)
            .placeholder {
                ProgressView()
            }
            .resizable()
            .scaledToFill()
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
