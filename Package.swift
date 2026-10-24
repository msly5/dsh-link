// swift-tools-version: 6.0
import PackageDescription

// Core protocol regressions run on macOS without booting an iPhone simulator.
let package = Package(
    name: "DSHRemoteCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "DSHRemoteCore", targets: ["DSHRemoteCore"])],
    targets: [
        .target(name: "DSHRemoteCore", path: "DSHRemote", exclude: [
            "SessionActionRow.swift",
            "Assets.xcassets", "QRCodeScannerView.swift", "NavigationRowButtonStyle.swift", "SidebarContainer.swift", "DesignPreview.swift", "SessionSidebar.swift", "ConversationWelcome.swift", "SessionBrowser.swift", "WorkspaceBrowser.swift", "ChatView.swift", "Components.swift", "DSHRemoteApp.swift",
            "LocalImageView.swift", "ChatImageView.swift", "PhotoAttachmentPicker.swift", "ImagePreview.swift", "PendingImageStrip.swift",
            "ModelPickerView.swift", "NewSessionView.swift", "PushSupport.swift", "QuestionCard.swift", "ToolResultGroupView.swift", "ExecutionRow.swift", "MarkdownTableView.swift", "MarkdownTableLayout.swift",
            "PrimaryButtonStyle.swift", "IconButtonStyle.swift", "BrandMark.swift", "ConnectionCard.swift", "SessionRowView.swift", "ChatComposer.swift", "ContextGauge.swift", "MessageRow.swift", "ApprovalCard.swift", "RichText.swift", "SessionListView.swift", "SettingsView.swift", "Theme.swift", "WSLogDelegate.swift",
        ]),
        .testTarget(name: "DSHRemoteCoreTests", dependencies: ["DSHRemoteCore"], path: "Tests"),
    ],
    swiftLanguageModes: [.v5]
)
