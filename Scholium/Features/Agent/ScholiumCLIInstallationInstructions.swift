import ScholiumContracts

/// Researcher-copyable instructions for the independently distributed CLI.
/// Scholium never executes these commands or infers machine state from them.
enum ScholiumCLIInstallationInstructions {
    static var text: String {
        """
        Install or update the compatible Scholium CLI from Scholium's official release.

        You are authorized to download only this archive:
        \(ScholiumCLIDistribution.downloadURL)

        You may install only these two release-owned items under $HOME/.local/bin:
        - scholium
        - Scholium_ScholiumCore.bundle

        Do not use sudo. Do not edit PATH, shell profiles, Agent configuration, or macOS quarantine metadata.

        1. First run:
           $HOME/.local/bin/scholium version --format json
           $HOME/.local/bin/scholium doctor --format json
           If the version command succeeds, accept it only when `product` is `Scholium` and `cli_version` is `\(ScholiumProductIdentity.marketingVersion)`. Ignore additional JSON fields. If both commands succeed, keep the existing installation and skip to step 3.
        2. Otherwise install the official archive:
           scholium_cli_setup="$(mktemp -d)"
           curl --fail --location --output "$scholium_cli_setup/Scholium-CLI.zip" "\(ScholiumCLIDistribution.downloadURL)"
           ditto -x -k "$scholium_cli_setup/Scholium-CLI.zip" "$scholium_cli_setup"
           "$scholium_cli_setup/Scholium-CLI/install.sh"
           rm -rf "$scholium_cli_setup"
        3. Verify the installed CLI with its absolute path:
           $HOME/.local/bin/scholium version --format json
           $HOME/.local/bin/scholium doctor --format json
           $HOME/.local/bin/scholium help agent

        If a command fails, stop and report the exact command and error. Do not weaken macOS protections or substitute another download source.
        """
    }
}
