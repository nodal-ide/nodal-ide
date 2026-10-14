//
//  ContributorRowView.swift
//  CodeEdit
//
//  Created by Lukas Pistrol on 19.01.23.
//

import SwiftUI
import CodeEditSymbols

struct ContributorRowView: View {

    let contributor: Contributor

    var body: some View {
        HStack {
            userImage
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(contributor.name)
                        .font(.headline)
                }
                FlowLayout(spacing: 4) {
                    ForEach(contributor.contributions, id: \.self) { item in
                        tag(item)
                    }
                }
            }
            Spacer()
            HStack(alignment: .top) {
                if let profileURL = contributor.profileURL, profileURL != contributor.gitHubURL {
                    ActionButton(url: profileURL, image: .init(systemName: "globe"))
                }
                if let gitHubURL = contributor.gitHubURL {
                    ActionButton(url: gitHubURL, image: .github)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var userImage: some View {
        AsyncImage(url: contributor.avatarURL) { image in
            image
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .help(contributor.name)
        } placeholder: {
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: 32, height: 32)
                .help(contributor.name)
        }
    }

    private func tag(_ item: Contributor.Contribution) -> some View {
        Text(item.rawValue.capitalized)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundColor(item.color)
            .background {
                Capsule(style: .continuous)
                    .strokeBorder(lineWidth: 1)
                    .foregroundStyle(item.color)
                    .opacity(0.8)
            }
    }

    private struct ActionButton: View {
        @Environment(\.openURL)
        private var openURL
        @State private var hovering = false

        let url: URL
        let image: Image

        var body: some View {
            Button {
                openURL(url)
            } label: {
                image
                    .imageScale(.medium)
                    .foregroundColor(hovering ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .onHover { hover in
                hovering = hover
            }
        }
    }
}

/// A minimal flow layout that wraps its subviews onto multiple lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX + size.width > maxWidth, cursorX > 0 {
                cursorX = 0
                cursorY += rowHeight + spacing
                rowHeight = 0
            }
            cursorX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        let width = maxWidth.isFinite ? maxWidth : max(0, cursorX - spacing)
        return CGSize(width: width, height: cursorY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var cursorX = bounds.minX
        var cursorY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX + size.width > bounds.maxX, cursorX > bounds.minX {
                cursorX = bounds.minX
                cursorY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: cursorX, y: cursorY), proposal: ProposedViewSize(size))
            cursorX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct ContributorRowView_Previews: PreviewProvider {
    static var previews: some View {
        let contributor = Contributor(
            login: "lukepistrol",
            name: "Lukas Pistrol",
            avatarURLString: "https://avatars.githubusercontent.com/u/9460130?v=4",
            profile: "http://lukaspistrol.com",
            contributions: [.infra, .test, .code]
        )
        ContributorRowView(contributor: contributor)
            .frame(width: 350)
    }
}
