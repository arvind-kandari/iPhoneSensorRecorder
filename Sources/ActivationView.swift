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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 60)

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

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .preferredColorScheme(.dark)
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
