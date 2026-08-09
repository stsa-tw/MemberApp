import SwiftUI

struct ChannelsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthManager.self) private var auth

    /// Seeded from the member's own school, so a first visit is already
    /// sensible rather than empty.
    private var defaults: Set<String> {
        Channel.defaultSubscriptions(school: auth.profile?.school)
    }

    private var subscribed: Set<String> {
        settings.subscribedChannels ?? defaults
    }

    var body: some View {
        List {
            Section {
                ForEach(Channel.all) { channel in
                    row(channel)
                }
            } header: {
                Text("頻道")
            } footer: {
                // Says what it does today rather than implying push works.
                Text("選擇你想收到的公告類型。推播通知尚未開放，目前這只會影響 App 內顯示的內容。")
            }
        }
        .navigationTitle("頻道")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ channel: Channel) -> some View {
        Toggle(isOn: Binding(
            get: { subscribed.contains(channel.id) },
            set: { settings.setSubscribed($0, channel: channel, defaultingTo: defaults) }
        )) {
            HStack(spacing: 12) {
                Group {
                    if let symbol = channel.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 17, weight: .semibold))
                    } else {
                        Text(channel.badge)
                            .font(.caption.weight(.bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(channel.tint)
                .clipShape(.circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.callout.weight(.semibold))
                    Text(channel.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChannelsView()
            .environment(AppSettings())
            .environment(AuthManager())
    }
}
