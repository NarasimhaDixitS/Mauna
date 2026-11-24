import SwiftUI

/// Which music player Mauna controls. YouTube Music joins in Phase 5.
struct PlayersSettings: View {
    let session: PlayerSession

    var body: some View {
        SettingsPage(symbol: "music.note", title: "Players", subtitle: "The music Mauna pauses, fades and brings back.") {
            SettingsCard {
                ForEach(Array(PlayerID.allCases.enumerated()), id: \.element) { index, player in
                    SettingsRow(showsDivider: index < PlayerID.allCases.count - 1) {
                        PlayerChoice(player: player, isSelected: session.player == player) {
                            session.select(player)
                        }
                    }
                }
            }
            Text("Mauna never reads what you listen to.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

private struct PlayerChoice: View {
    let player: PlayerID
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                AppIconView(bundleID: player.bundleID, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.displayName).font(.body.weight(.medium))
                    Text(player.isInstalled ? (player.isRunning ? "Open" : "Installed") : "Not installed")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.accentFill) : AnyShapeStyle(.tertiary))
                    .animation(.maunaEaseOut(0.16), value: isSelected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainTextButtonStyle())
        .disabled(!player.isInstalled)
        .opacity(player.isInstalled ? 1 : 0.5)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
