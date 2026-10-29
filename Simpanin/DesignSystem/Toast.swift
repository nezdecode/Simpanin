//
//  Toast.swift
//  Simpanin
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// A short note at the bottom of the screen, like "Nama disalin". Each one is new, so a second copy
/// replaces the first and gets its own time on screen.
struct Toast: Equatable {
    let id = UUID()
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?

    static func == (first: Toast, second: Toast) -> Bool { first.id == second.id }
}

/// Shows a toast for about three seconds and has VoiceOver read it.
struct ToastPresenter: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    VStack(spacing: 2) {
                        Text(toast.title).font(.subheadline.weight(.semibold))
                        if let detail = toast.detail {
                            Text(detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
                    .padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("toast")
                }
            }
            .animation(.default, value: toast)
            .task(id: toast) {
                guard let shown = toast else { return }
                let spoken = [shown.title, shown.detail].compactMap { $0.map { String(localized: $0) } }
                AccessibilityNotification.Announcement(spoken.joined(separator: ", ")).post()
                // Cancelled when another toast replaces it or the screen goes; only time runs it out.
                guard (try? await Task.sleep(for: .seconds(3))) != nil else { return }
                toast = nil
            }
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View { modifier(ToastPresenter(toast: toast)) }
}
