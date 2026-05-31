import SwiftUI

struct UploaderSettingsForm: View {
    @EnvironmentObject var config: ConfigService
    @State private var revealToken = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            githubSection
            cdnSection
            compressSection
            pathsSection
        }
        .frame(maxWidth: 540, alignment: .leading)
    }

    private var githubSection: some View {
        SettingsSection(title: "GitHub Repository") {
            Toggle("Enable image uploader", isOn: bind(\.uploader.enabled))
            FieldRow(label: "Owner") {
                TextField("lightblues", text: bind(\.uploader.github.owner))
                    .textFieldStyle(.roundedBorder)
            }
            FieldRow(label: "Repo") {
                TextField("assets", text: bind(\.uploader.github.repo))
                    .textFieldStyle(.roundedBorder)
            }
            FieldRow(label: "Branch") {
                TextField("main", text: bind(\.uploader.github.branch))
                    .textFieldStyle(.roundedBorder)
            }
            FieldRow(label: "Token") {
                HStack(spacing: 6) {
                    if revealToken {
                        TextField("ghp_…", text: bind(\.uploader.github.token))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    } else {
                        SecureField("ghp_…", text: bind(\.uploader.github.token))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    Button {
                        revealToken.toggle()
                    } label: {
                        Image(systemName: revealToken ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Personal access token with `Contents: write` scope on the target repo. Stored in `config.json` — keep mackup-synced configs out of public dotfiles.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cdnSection: some View {
        SettingsSection(title: "CDN") {
            FieldRow(label: "Base URL") {
                TextField("https://cdn.jsdelivr.net/gh", text: bind(\.uploader.cdn.baseUrl))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }
            Text("Final URLs are: `{baseUrl}/{owner}/{repo}@{branch}/{path}/{filename}`.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var compressSection: some View {
        SettingsSection(title: "Compression") {
            FieldRow(label: "Quality") {
                HStack {
                    Slider(value: qualityBinding, in: 30...100, step: 1)
                        .frame(width: 200)
                    Text("\(config.config.uploader.compress.quality)")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .leading)
                }
            }
            FieldRow(label: "Default format") {
                Picker("", selection: bind(\.uploader.compress.defaultFormat)) {
                    Text("Auto").tag("auto")
                    Text("JPEG").tag("jpeg")
                    Text("WebP").tag("webp")
                    Text("PNG").tag("png")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    private var qualityBinding: Binding<Double> {
        Binding(
            get: { Double(config.config.uploader.compress.quality) },
            set: { newValue in
                var draft = config.config
                draft.uploader.compress.quality = Int(newValue)
                config.save(draft)
            }
        )
    }

    private var pathsSection: some View {
        SettingsSection(title: "Paths") {
            FieldRow(label: "Default path") {
                TextField("upload", text: bind(\.uploader.defaultPath))
                    .textFieldStyle(.roundedBorder)
            }
            Toggle("Cache thumbnails for upload history",
                   isOn: bind(\.uploader.cacheThumbnails))
        }
    }

    private func bind<T>(_ keyPath: WritableKeyPath<AppConfig, T>) -> Binding<T> {
        Binding(
            get: { config.config[keyPath: keyPath] },
            set: { newValue in
                var draft = config.config
                draft[keyPath: keyPath] = newValue
                config.save(draft)
            }
        )
    }
}
