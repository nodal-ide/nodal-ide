//
//  StatusBarView.swift
//  CodeEdit
//
//  Created by Lukas Pistrol on 19.03.22.
//

import SwiftUI

/// # StatusBarView
///
/// A View that lives on the bottom of the window and offers information
/// about compilation errors/warnings, git,  cursor position in text,
/// indentation width (in spaces), text encoding and linebreak.
///
/// Also information about the file size and dimensions, if available.
///
/// Additionally it offers a togglable/resizable drawer which can
/// host a terminal or additional debug information
///
struct StatusBarView: View {
    @Environment(\.controlActiveState)
    private var controlActive

    @EnvironmentObject private var utilityAreaViewModel: UtilityAreaViewModel

    static var height: CGFloat {
        if #available(macOS 26, *) {
            37.0
        } else {
            29.0
        }
    }

    private var trailingPadding: CGFloat {
        if #available(macOS 26, *) {
            8
        } else {
            0
        }
    }

    @Environment(\.colorScheme)
    private var colorScheme

    var proxy: SplitViewProxy

    static let statusbarID = "statusbarID"

    /// The actual status bar
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ForEach(utilityAreaViewModel.tabItems) { tab in
                Button {
                    utilityAreaViewModel.open(tab: tab)
                } label: {
                    Image(systemName: tab.systemImage)
                }
                .buttonStyle(.icon(isActive: utilityAreaViewModel.selectedTab == tab))
                .help(tab.title)
            }
            StatusBarBreakpointButton()
            StatusBarDivider()
            Spacer()
            StatusBarFileInfoView()
            StatusBarCursorPositionLabel()
            StatusBarDivider()
            StatusBarToggleUtilityAreaButton()
        }
        .padding(.horizontal, 10)
        .padding(.trailing, trailingPadding)
        .frame(height: Self.height - 1.0)
        .background(.bar)
        .padding(.top, 1)
        .overlay(alignment: .top) {
            Divider()
                .overlay(Color(nsColor: colorScheme == .dark ? .black : .clear))
        }
        // A dedicated resize handle at the top edge (so the cursor only hints resize there, not over
        // the status items). The whole bar still responds to the drag for convenience.
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.clear)
                .frame(height: 7)
                .contentShape(Rectangle())
                .cursor(.resizeUpDown)
                .gesture(dragGesture)
        }
        .gesture(dragGesture)
        .disabled(controlActive == .inactive)
    }

    /// A drag gesture to resize the drawer beneath the status bar
    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                proxy.setPosition(of: 0, position: value.location.y + Self.height / 2)
            }
    }
}

struct StatusBarDivider: View {
    var body: some View {
        Divider()
            .frame(maxHeight: 12)
//            .padding(.horizontal, 7)
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover {
            if $0 {
                cursor.push()
            } else {
                cursor.pop()
            }
        }
    }
}
