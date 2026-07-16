// SettingsCard+ZFSMount — the sudo-explainer settings block (ho-17), extracted
// from SettingsCard.swift to keep that file within the line-length budget. The
// narrow, copyable sudoers line, prefilled from the focused host's ssh-config.

import AppKit
import PalanaCore
import SwiftUI

extension SettingsForm {
    /// The sudo-explainer (ho-17): the narrow sudoers line that unlocks
    /// mount/unmount, prefilled with the focused host's login when the ssh
    /// config names it, else the clear `<user>` placeholder.
    var zfsMountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ZFS mount & unmount")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            Text(
                "Mounting is root's on Linux. pālana can mount and unmount for you if "
                    + "the host grants passwordless sudo for just those two commands — add "
                    + "this to the host's sudoers (visudo), then reprobe the host:"
            )
            .font(.system(size: 11))
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 8) {
                Text(sudoersLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.groundDeep)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Button("copy") { copySudoersLine() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
            }
            Text(sudoersHint)
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The login for the line: the focused host's ssh-config `User`, or the
    /// placeholder when it isn't known — never a wrong guess in a root grant.
    private var sudoersUser: String {
        session.focusedPane.state.host
            .flatMap { SSHConfigParser.user(for: $0, in: model.configText) }
            ?? SudoGuidance.userPlaceholder
    }

    private var sudoersLine: String { SudoGuidance.sudoersLine(user: sudoersUser) }

    private var sudoersHint: String {
        let base =
            "Check the path with `which zfs` (it's /sbin/zfs on some distros). "
            + "Optional — or just mount from the shell (⌘`)."
        return sudoersUser == SudoGuidance.userPlaceholder
            ? "Replace <user> with your login on that host. " + base
            : base
    }

    private func copySudoersLine() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sudoersLine, forType: .string)
    }
}
