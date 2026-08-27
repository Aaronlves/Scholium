import ScholiumContracts

/// Researcher-copyable instructions for the independently distributed CLI.
/// Scholium never executes these commands or infers machine state from them.
enum ScholiumCLIInstallationInstructions {
    static var text: String {
        """
        Use the compatible Scholium CLI at `$HOME/.local/bin/scholium`.

        If `version --format json` and `doctor --format json` do not confirm `product=Scholium` and `cli_version=\(ScholiumProductIdentity.marketingVersion)`, install the official archive. Ignore other version fields.
        \(ScholiumCLIDistribution.downloadURL)

        Run the archive's `install.sh`. It may install only `scholium` and `Scholium_ScholiumCore.bundle` under `$HOME/.local/bin`.
        Do not use `sudo`, edit PATH, shell profiles, global Agent configuration, or macOS quarantine metadata, or use another download source.

        Then run `$HOME/.local/bin/scholium version --format json`, `doctor --format json`, and `help agent`. Stop and report any failure.
        """
    }
}
