import AVFoundation
import SwiftUI

/// The 幹部 scanner — point the camera at a member's card and it says whose it is.
///
/// Read-only by design, like the web scanner it mirrors: it answers "is this a
/// member, right now" and records nothing. Check-in would need an endpoint that
/// consumes the code and stores the attendance, and there is nothing on the
/// device that could stand in for one.
struct ScanView: View {
    @Environment(\.scenePhase) private var scenePhase

    /// Owned here rather than injected. Unlike `MembershipCodeStore` it has no
    /// life beyond this screen, and there is no reason to put an officer-only
    /// object in every member's environment.
    @State private var validator = MembershipValidator()
    @State private var access = CameraAccess.current

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch access {
                case .undetermined:
                    ProgressView()
                        .padding(.top, 80)
                case .denied:
                    deniedState
                case .granted:
                    if let outcome = validator.outcome {
                        ResultPanel(outcome: outcome) { validator.reset() }
                    } else {
                        viewfinder
                        hint
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.top, 6)
            // The 我的 tab carries the 會員卡 accessory, which no safe area
            // accounts for — see `Metrics.accessoryClearance`.
            .padding(.bottom, Theme.Metrics.accessoryClearance)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("掃描會員卡")
        .navigationBarTitleDisplayMode(.inline)
        .task { await requestAccess() }
        // Someone who took the 前往設定 route grants the permission outside the
        // app; without this they would come back to the same dead end.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            access = CameraAccess.current
        }
    }

    // MARK: - Camera

    private var viewfinder: some View {
        CameraScanner { payload in
            Task { await validator.validate(payload: payload) }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: Theme.Radius.memberCard))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.memberCard)
                .strokeBorder(.white.opacity(0.55), lineWidth: 2)
                .padding(24)
        }
        .overlay {
            if validator.isValidating {
                ZStack {
                    Color.black.opacity(0.45)
                    ProgressView()
                        .tint(.white)
                }
                .clipShape(.rect(cornerRadius: Theme.Radius.memberCard))
            }
        }
        .accessibilityLabel("相機取景框")
        .accessibilityHint("對準會員卡上的 QR code")
    }

    private var hint: some View {
        VStack(spacing: 6) {
            Text("將會員卡上的 QR code 對準框內。")
            Text("掃描只會確認會員身分,不會留下紀錄。")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    // MARK: - Permission

    private var deniedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("需要相機權限才能掃描")
                .font(.headline)
            Text("在「設定」中允許 STSA 使用相機,就可以掃描會員卡。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("前往設定") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.brandPlain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func requestAccess() async {
        guard access == .undetermined else { return }
        access = await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
    }
}

// MARK: - Result

/// What the operator reads off the screen: whether the code holds up, and who
/// it belongs to.
private struct ResultPanel: View {
    let outcome: MembershipValidator.Outcome
    let onScanAgain: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 72))
                    .foregroundStyle(tint)
                Text(headline)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                if case .unreachable(let message) = outcome {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)

            if case .valid(let member) = outcome {
                // `GroupedCard` insets itself by the gutter this screen has
                // already applied, so the container is spelled out here instead.
                VStack(spacing: 0) {
                    field("姓名", member.name)
                    RowSeparator()
                    field("帳號", member.username)
                    RowSeparator()
                    field("信箱", member.email)
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: Theme.Radius.list))
                // Combined so VoiceOver reads the whole identity out in one
                // breath rather than in three swipes.
                .accessibilityElement(children: .combine)
            }

            Button("再掃一次", action: onScanAgain)
                .buttonStyle(.brand)
        }
    }

    private func field(_ label: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(.body.weight(.medium))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Text(label)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var symbol: String {
        switch outcome {
        case .valid: "checkmark.circle.fill"
        case .invalid: "xmark.circle.fill"
        case .unreachable: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch outcome {
        case .valid: .green
        case .invalid: .red
        case .unreachable: .orange
        }
    }

    private var headline: LocalizedStringKey {
        switch outcome {
        case .valid: "有效會員碼"
        case .invalid: "無效或已過期的會員碼"
        case .unreachable: "無法驗證會員碼"
        }
    }
}

// The camera cannot run in a preview, so these cover the half that has a design
// to check — what the operator reads after the scan lands.
#Preview("有效") {
    ResultPreview(outcome: .valid(ScannedMember(
        name: "Kimi Yang", username: "kimiyang", email: "kimi@u.nus.edu"
    )))
}

#Preview("無效") {
    ResultPreview(outcome: .invalid)
}

private struct ResultPreview: View {
    let outcome: MembershipValidator.Outcome

    var body: some View {
        NavigationStack {
            ScrollView {
                ResultPanel(outcome: outcome) {}
                    .padding(.horizontal, Theme.Metrics.gutter)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("掃描會員卡")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Theme.Palette.brand)
    }
}

// MARK: - Permission state

