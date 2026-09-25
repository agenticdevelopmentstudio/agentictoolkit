//
//  SessionsViewController.swift
//  AgenticToolkit
//
//  Created by Mike Fullerton on 4/29/26.
//

import AppKit
import AgenticToolkitCore

extension SessionWatcher {

    public class SessionListViewController: WindowContentViewController<SessionListView> {

        public let viewModel: SessionListViewModel

        /// - Parameter tracksFrontmostWindow: highlight the session whose terminal
        ///   window is frontmost. Needs Accessibility — pass `true` only from a
        ///   host that holds the grant (see `SessionListViewModel`).
        public init(source: SessionListSource, tracksFrontmostWindow: Bool = false) {
            let viewModel = SessionListViewModel(
                source: source,
                settingsStore: UserSettings.shared,
                tracksFrontmostWindow: tracksFrontmostWindow
            )

            self.viewModel = viewModel
            super.init(contentView: SessionListView(viewModel: viewModel))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public override func viewWillAppear() {
            super.viewWillAppear()
            // Start observation (initial load + source subscription + timers) only
            // while the window is visible, so a pre-constructed-but-hidden window
            // (e.g. one created at launch for restore) does no background polling.
            viewModel.startListening()
        }

        public override func viewDidDisappear() {
            super.viewDidDisappear()
            // Tear down observation when the window is hidden/closed; viewWillAppear
            // restarts it if the window is shown again.
            viewModel.stopListening()
        }
    }
}
