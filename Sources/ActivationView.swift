import SwiftUI

struct ActivationView: View {
    @ObservedObject var licenseManager: LicenseManager

    @State private var fullName = ""
    @State private var username = ""
    @State private var licenseKey = ""
    @State private var errorMessage = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case fullName
        case username
        case licenseKey
    }

    private var deviceIdentity: DeviceIdentity {
        .shared
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 54))
                        .foregroundStyle(.red)

                    VStack(spacing: 8) {
                        Text(AppInfo.name)
                            .font(.largeTitle.bold())

                        Text("Activation Required")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("THIS IPHONE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        deviceInfoRow(
                            title: "Device ID",
                            value: deviceIdentity.deviceID
                        )

                        deviceInfoRow(
                            title: "Device Public Key",
                            value: deviceIdentity.publicKeyBase64URL,
                            monospaced: true
                        )
                    }
                    .padding(16)
                    .background(
                        Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 14)
                    )

                    VStack(alignment: .leading, spacing: 16) {
                        inputField(
                            title: "Full Name *",
                            text: $fullName,
                            field: .fullName
                        )

                        inputField(
                            title: "Username *",
                            text: $username,
                            field: .username
                        )

                        VStack(alignment: .leading, spacing: 7) {
                            Text("License Key *")
                                .font(.subheadline.weight(.semibold))

                            TextEditor(text: $licenseKey)
                                .focused($focusedField, equals: .licenseKey)
                                .frame(minHeight: 130)
                                .padding(8)
                                .scrollContentBackground(.hidden)
                                .background(
                                    Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: activate) {
                        Text("ACTIVATE")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(
                        fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Text("Activation is verified offline on this iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func deviceInfoRow(
        title: String,
        value: String,
        monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            Text(value)
                .font(
                    monospaced
                    ? .system(.caption, design: .monospaced)
                    : .subheadline
                )
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inputField(
        title: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            TextField("", text: text)
                .focused($focusedField, equals: field)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(
                    Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }

    private func activate() {
        errorMessage = ""

        do {
            try licenseManager.activate(
                fullName: fullName,
                username: username,
                licenseKey: licenseKey
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
