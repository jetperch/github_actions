<!--
SPDX-FileCopyrightText: Copyright 2026 Jetperch LLC
SPDX-License-Identifier: Apache-2.0
-->

# CHANGELOG


## 1.0.0

2026 Oct 8

* Added windows_sign, which signs Windows PE files with AzureSignTool and
  Azure Key Vault, then verifies each signature.  Based on
  `azure_sign()` in pyjoulescope_ui `ci/windows_installer.py`.
