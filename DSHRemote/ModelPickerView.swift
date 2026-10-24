import SwiftUI

// MARK: - 选择页

struct ModelPickerView: View {
    let sessionId: String

    @Environment(\.dismiss) private var dismiss
    @State private var catalog: ModelCatalog?
    @State private var errorText: String?
    @State private var working = false
    @State private var showError = false
    @State private var selection: SessionModelSelection?

    var body: some View {
        NavigationStack {
            List {
                if let catalog {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("模型配置", systemImage: "sparkle").font(.caption).foregroundStyle(Theme.accent)
                            Text(selection?.model == nil ? "默认模型" : "当前会话")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                            Text(selection?.model ?? catalog.default.model)
                                .font(.body.weight(.medium))
                            Text((selection?.provider ?? catalog.default.provider) + effortSuffix(selection?.reasoningEffort ?? catalog.default.reasoningEffort))
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .listRowBackground(Theme.card)

                    ForEach(catalog.groups) { group in
                        Section(group.name) {
                            ForEach(group.models) { model in
                                modelRow(group: group, model: model).listRowBackground(Theme.card)
                            }
                        }
                    }

                    if let failures = catalog.failures, !failures.isEmpty {
                        Section("不可用") {
                            ForEach(failures, id: \.id) { failure in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(failure.name ?? failure.id).font(.footnote)
                                    if let message = failure.message {
                                        Text(message).font(.footnote).foregroundStyle(Theme.muted)
                                    }
                                }
                            }
                        }
                    }
                } else if let errorText {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                        Button("重新加载") { Task { await load() } }
                    }
                } else {
                    HStack { ProgressView(); Text("读取模型目录…").font(.footnote) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .listSectionSpacing(22)
            .navigationTitle("模型与思考")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await load() }
            .alert("操作失败", isPresented: $showError) {
                Button("知道了", role: .cancel) { }
            } message: { Text(errorText ?? "请重试") }
            .interactiveDismissDisabled(working)
            .disabled(working)
        }
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func modelRow(group: ModelProviderGroup, model: ModelCatalogModel) -> some View {
        let efforts = model.reasoning?.efforts ?? []
        if efforts.isEmpty {
            Button {
                Task { await select(provider: group.id, model: model.id, effort: nil) }
            } label: {
                rowLabel(model, detail: model.description)
            }
            .tint(Theme.text)
        } else {
            NavigationLink {
                EffortListView(
                    model: model,
                    effortHint: selection?.model == model.id ? selection?.reasoningEffort : model.reasoning?.defaultEffort
                ) { effort in
                    Task { await select(provider: group.id, model: model.id, effort: effort) }
                }
            } label: {
                rowLabel(model, detail: model.description, trailing: "\(efforts.count) 档思考")
            }
        }
    }

    private func rowLabel(_ model: ModelCatalogModel, detail: String?, trailing: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.name).font(.body.weight(.medium)).foregroundStyle(Theme.text)
            if let detail, !detail.isEmpty {
                Text(detail).font(.footnote).foregroundStyle(Theme.muted).lineLimit(2)
            }
            if let trailing {
                Text(trailing).font(.footnote).foregroundStyle(Theme.muted)
            }
        }
    }

    private func effortSuffix(_ effort: String?) -> String {
        guard let effort, !effort.isEmpty else { return "" }
        return " · \(effort)"
    }

    private func load() async {
        #if DEBUG
        if DesignPreview.enabled { catalog = DesignPreview.catalog; return }
        #endif
        errorText = nil
        do {
            catalog = try await RemoteClient.shared.modelCatalog()
            if let summary = try? await RemoteClient.shared.sessionSnapshot(sessionId) {
                selection = summary.projections?.values?.modelSelection?.next
                    ?? summary.projections?.values?.modelSelection?.lastUsed
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func select(provider: String, model: String, effort: String?) async {
        #if DEBUG
        if DesignPreview.enabled { dismiss(); return }
        #endif
        guard !working else { return }
        working = true
        defer { working = false }
        do {
            try await RemoteClient.shared.selectModel(
                sessionId: sessionId,
                provider: provider,
                model: model,
                effort: effort
            )
            dismiss()
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }
}

struct EffortListView: View {
    let model: ModelCatalogModel
    let effortHint: String?
    let onPick: (String) -> Void

    var body: some View {
        List {
            ForEach(model.reasoning?.efforts ?? []) { effort in
                Button {
                    onPick(effort.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(effort.name)
                            if let description = effort.description, !description.isEmpty {
                                Text(description).font(.footnote).foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer()
                        if effort.id == effortHint {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                        }
                    }
                }
                .tint(Theme.text)
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
