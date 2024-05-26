# Copyright 2023 Dan Cassidy

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# SPDX-License-Identifier: GPL-3.0-or-later



# file list:
#   text files:
#     .version.ps1
#     ./support/docs/README.md
#     ./data/fomod/info.xml
#   plugin files:
#     # main plugin
#     "./data/JunkInYourTrunk_v2.esm"
#     # optional plugins
#     "./data/JIYTv2CargoExpanderX10.esm"
#     "./data/JIYTv2CargoExpanderX3.esm"
#     "./data/JIYTv2NoDecoratives.esm"
#     # compatibility patches
#     "./data/JIYTv2-SKKShipPartsNoLevelAllVendors-Patch.esm"
#     "./data/JIYTv2-ShipColorize-Patch.esm"
#     "./data/JIYTv2-StarfieldExtendedShieldsRebalanced-Patch.esm"
#     "./data/JIYTv2-USU-Patch.esm"
#     "./data/JIYTv2-USUNoLevelRequirements-Patch.esm"
#     "./data/JIYTv2-USUQuestRewards-Patch.esm"


# get a hash from a string
# https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash?view=powershell-7.3#examples

function Get-StringHash([string] $content) {
    $string_as_stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.StreamWriter]::new($string_as_stream)
    $writer.write($content)
    $writer.Flush()
    $string_as_stream.Position = 0
    (Get-FileHash -InputStream $string_as_stream).Hash
}

# stop the script if an uncaught error happens
$ErrorActionPreference = "Stop"

# source version class
. "./support/scripts/version-class.ps1"

# update build number
$version.IncrementBuild()
"version: " + $version.ToString($false)
"version with build: " + $version.ToString($true)

# backup options
[bool] $make_backups = $true
[string] $backup_suffix = ".$((Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmss\Z")).backup"



# make file changes

# text files
[System.Collections.Generic.List[hashtable]] $text_files = New-Object System.Collections.Generic.List[hashtable]
$text_files.Add(@{
        # .version.ps1
        # build_number = ...
        file               = "./.version.ps1"
        search_and_replace = @(@{
                search  = "(build_number = )\d*"
                replace = "`${1}" + $version.BuildNumber.ToString()
            })
    })
$text_files.Add(@{
        # ./support/docs/README.md
        # Version: ...
        file               = "./support/docs/README.md"
        search_and_replace = @(@{
                search  = "(Version: ).*"
                replace = "`${1}" + $version.ToString()
            })
    })
$text_files.Add(@{
        # ./data/fomod/info.xml
        # <Version>...</Version>
        file               = "./data/fomod/info.xml"
        search_and_replace = @(@{
                search  = "(<Version>).*(</Version>)"
                replace = "`${1}" + $version.ToString() + "`$2"
            })
    })

"------------------------------"
$text_files | ForEach-Object {
    $file = Get-Item $_.file
    "Version Updater: Examining '$($_.file)'"
    $updated = 0
    $encoding = if ($_.encoding) { $_.encoding } else { "UTF8NoBOM" }
    $_.search_and_replace | ForEach-Object {
        $content = Get-Content -LiteralPath $file -Encoding $encoding -Raw
        $original_hash = Get-StringHash $content
        $content = $content -replace $_.search, $_.replace
        $new_hash = Get-StringHash $content
        if ($new_hash -ne $original_hash) {
            if ($make_backups) { Copy-Item -LiteralPath $file "$file$backup_suffix" }
            $content | Set-Content -LiteralPath $file -Encoding $encoding -NoNewline
            $updated += 1
        }
        # (Get-Content -LiteralPath $file -Encoding $encoding) -replace $_.search, $_.replace | Set-Content -LiteralPath $file -Encoding $encoding
    }
    if ($updated) { "File updated with new version string$(if ($updated -gt 1) { "s" })." } else { "No file updated needed." }
    "------------------------------"
}

# plugin files
[string[]] $plugin_files = @(
    # main plugin
    "./data/JunkInYourTrunk_v" + $version.VersionMajor + ".esm"
    # optional plugins
    "./data/JIYTv" + $version.VersionMajor + "CargoExpanderX3.esm"
    "./data/JIYTv" + $version.VersionMajor + "CargoExpanderX10.esm"
    "./data/JIYTv" + $version.VersionMajor + "NoDecoratives.esm"
    # compatibility patches
    "./data/JIYTv" + $version.VersionMajor + "-ShipColorize-Patch.esm"
    "./data/JIYTv" + $version.VersionMajor + "-ShipColorize-BetterShipPartSnaps-Patch.esm"
    "./data/JIYTv" + $version.VersionMajor + "-ShipColorize-CargoExpanderX3-Patch.esm"
    "./data/JIYTv" + $version.VersionMajor + "-ShipColorize-CargoExpanderX10-Patch.esm"
    "./data/JIYTv" + $version.VersionMajor + "-SKKShipPartsNoLevelAllVendors-Patch.esm"
    "./data/JIYTv" + $version.VersionMajor + "-StarfieldExtendedShieldsRebalanced-Patch.esm"
    "./data/JIYTv" + $version.VersionMajor + "-USU-Patch.esm"
    "./data/JIYTv" + $version.VersionMajor + "-USUNoLevelRequirements-Patch.esm"
    "./data/JIYTv" + $version.VersionMajor + "-USUQuestRewards-Patch.esm"
)
# python3 needs to be accessible from PATH!
python3.exe "./support/scripts/plugin-description-version-updater.py" $(if (-not $make_backups) { "-n" }) "$version" $plugin_files
