<!--
SPDX-FileCopyrightText: Copyright 2026 Jetperch LLC
SPDX-License-Identifier: Apache-2.0
-->

# Jetperch GitHub Actions

Shared composite actions for Jetperch GitHub workflows.  Reference an
action with a version tag or a commit SHA, never a branch, so that a
change here cannot silently change a release build.

| Action | Purpose |
|---|---|
| [windows_sign](#windows_sign) | Sign Windows `.exe`, `.dll` and `.pyd` files |


## windows_sign

Signs Windows PE files with
[AzureSignTool](https://github.com/vcsjones/AzureSignTool) and the
certificate in Azure Key Vault, then verifies every signature with
`Get-AuthenticodeSignature`.  Windows Smart App Control and SmartScreen
check every binary that a process loads, so sign every `.exe`, `.dll` and
`.pyd` that ships, not just the launcher.

Runs on Windows runners, including `windows-11-arm`.  It installs
AzureSignTool with `dotnet tool` when the runner does not have it.

```yaml
      - name: Sign Windows binaries
        if: >-
          github.event_name == 'push' && (github.ref == 'refs/heads/main'
          || startsWith(github.ref, 'refs/tags/v'))
        uses: jetperch/github_actions/windows_sign@v1
        with:
          files: |
            build/Release/*.exe
            build/Release/*.dll
          azure_key_vault_uri: ${{ secrets.AZURE_KEY_VAULT_URI }}
          azure_client_id: ${{ secrets.AZURE_CLIENT_ID }}
          azure_tenant_id: ${{ secrets.AZURE_TENANT_ID }}
          azure_client_secret: ${{ secrets.AZURE_CLIENT_SECRET }}
          azure_cert_name: ${{ secrets.AZURE_CERT_NAME }}
```

Sign only trusted refs, such as `main` and release tags, with an `if:` as
above.  Pull requests receive no secrets.  An empty
`azure_key_vault_uri` skips signing with a notice, so the same workflow
also runs for pull requests.

| Input | Default | Description |
|---|---|---|
| `files` | (required) | Newline-separated paths or wildcard patterns; `<dir>/**/<name>` recurses |
| `azure_key_vault_uri` | `''` | Key Vault URI; empty skips signing |
| `azure_client_id` | `''` | Application (client) ID |
| `azure_tenant_id` | `''` | Tenant ID |
| `azure_client_secret` | `''` | Client secret |
| `azure_cert_name` | `''` | Certificate name in the key vault |
| `timestamp_url` | `http://timestamp.digicert.com` | RFC 3161 timestamp server |
| `if_no_files_found` | `error` | `error`, `warn` or `ignore` for a pattern without files |
| `azuresigntool_version` | `''` | AzureSignTool version; empty installs the latest |

| Output | Description |
|---|---|
| `signed` | `true` when files were signed and verified, else `false` |

Files that are already signed are skipped (`-s`).  All files are signed
in one AzureSignTool call with a file list, which avoids command-line
length limits and a Key Vault round trip per file.


## Releases

Tag each release `vX.Y.Z`, and move the major tag (`v1`) to it.  See
[CHANGELOG.md](CHANGELOG.md).
