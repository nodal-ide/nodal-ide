//
//  TaskOutputPane.swift
//  CodeEdit
//
//  The live task output, reused by the Console.
//

import SwiftUI

struct TaskOutputPane: View {
    @EnvironmentObject private var taskManager: TaskManager

    @AppSettings(\.theme.matchAppearance)
    private var matchAppearance
    @AppSettings(\.terminal.darkAppearance)
    private var darkAppearance
    @AppSettings(\.theme.useThemeBackground)
    private var useThemeBackground
    @AppSettings(\.textEditing.font)
    private var textEditingFont
    @AppSettings(\.terminal.font)
    private var terminalFont
    @AppSettings(\.terminal.useTextEditorFont)
    private var useTextEditorFont

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var scrollProxy: ScrollViewProxy?
    @StateObject private var themeModel: ThemeModel = .shared

    @Namespace var bottomID

    var body: some View {
        Group {
            if let taskID = taskManager.taskShowingOutput, let activeTask = taskManager.activeTasks[taskID] {
                GeometryReader { geometry in
                    let totalFontHeight = fontTotalHeight(nsFont: font).rounded(.up)
                    let constrainedHeight = geometry.size.height
                        - geometry.size.height.truncatingRemainder(dividingBy: totalFontHeight)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0).frame(minHeight: 0)
                        TaskOutputView(activeTask: activeTask)
                            .frame(height: max(0, constrainedHeight - 1))
                            .id(activeTask.task.id)
                            .padding(.horizontal, 10)
                    }
                }
                .paneToolbar {
                    taskPicker
                    TaskOutputActionsView(
                        activeTask: activeTask,
                        taskManager: taskManager,
                        scrollProxy: $scrollProxy,
                        bottomID: _bottomID
                    )
                }
                .background(background)
            } else {
                CEContentUnavailableView("No Task Output")
            }
        }
        .onReceive(taskManager.$activeTasks) { tasks in
            if taskManager.taskShowingOutput == nil {
                taskManager.taskShowingOutput = tasks.keys.first
            }
        }
    }

    @ViewBuilder private var taskPicker: some View {
        if taskManager.activeTasks.count > 1 {
            Picker("Task", selection: $taskManager.taskShowingOutput) {
                ForEach(Array(taskManager.activeTasks.keys), id: \.self) { taskID in
                    Text(taskManager.activeTasks[taskID]?.task.name ?? "Task").tag(Optional(taskID))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            Spacer()
        }
    }

    private var font: NSFont {
        useTextEditorFont == true ? textEditingFont.current : terminalFont.current
    }

    @ViewBuilder private var background: some View {
        if useThemeBackground {
            Color(nsColor: backgroundColor)
        } else if colorScheme == .dark {
            EffectView(.underPageBackground)
        } else {
            EffectView(.contentBackground)
        }
    }

    private var backgroundColor: NSColor {
        if let selectedTheme = matchAppearance && darkAppearance
            ? themeModel.selectedDarkTheme
            : themeModel.selectedTheme,
           let index = themeModel.themes.firstIndex(of: selectedTheme) {
            return NSColor(themeModel.themes[index].terminal.background.swiftColor)
        }
        return .windowBackgroundColor
    }

    private func fontTotalHeight(nsFont: NSFont) -> CGFloat {
        let ctFont = nsFont as CTFont
        return CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont)
    }
}
