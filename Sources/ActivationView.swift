import SwiftUI
import UIKit

struct ActivationView: View {
    @ObservedObject var licenseManager: LicenseManager

    @State private var fullName = ""
    @State private var username = ""
    @State private var licenseKey = ""
    @State private var errorMessage = ""
    @State private var deviceIdentity: DeviceIdentity?
    @State private var deviceIdentityError = ""

    @FocusState private var focusedField: Field?

    private enum Field {
        case fullName
        case username
        case licenseKey
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

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

                        if let identity = deviceIdentity {
                            deviceInfoRow(
                                title: "Device ID",
                                value: identity.deviceID
                            )

                            deviceInfoRow(
                                title: "Device Public Key",
                                value: identity.publicKeyBase64URL,
                                monospaced: true
                            )
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Device identity unavailable")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.red)

                                Text(
                                    deviceIdentityError.isEmpty
                                    ? "Initializing secure device identity..."
                                    : deviceIdentityError
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Button("RETRY") {
                                    loadDeviceIdentity()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                        }
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
                                .focused(
                                    $focusedField,
                                    equals: .licenseKey
                                )
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
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
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
                        deviceIdentity == nil ||
                        fullName
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty ||
                        username
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty ||
                        licenseKey
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
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
        .task {
            loadDeviceIdentity()
        }
    }

    private func loadDeviceIdentity() {
        deviceIdentityError = ""

        do {
            deviceIdentity = try DeviceIdentity.load()
        } catch {
            deviceIdentity = nil
            deviceIdentityError = error.localizedDescription
        }
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
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
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

        guard deviceIdentity != nil else {
            errorMessage = "Device identity is unavailable. Tap RETRY."
            return
        }

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