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


# update version information in files

param (
    [string] $TextFileSchemaFile = ".\support\scripts\version-updater-text-file-schema.ps1",
    [string[]] $PluginFiles = (Get-ChildItem -Path ".\data\*" -Include "*.esl", "*.esm", "*.esp" -File),
    [switch] $SkipBackup,
    [switch] $SkipBuildIncrement,
    [string] $BackupSuffix = ".$((Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmss\Z")).backup"
)

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
. (Join-Path $PSScriptRoot "version-class.ps1")

# update build number
if (-not $SkipBuildIncrement) { $version.IncrementBuild() }
"version: " + $version.ToString($false)
"version with build: " + $version.ToString($true)

# make file changes

# text files
[System.Collections.Generic.List[hashtable]] $text_files = New-Object System.Collections.Generic.List[hashtable]
# source the schema file
. $TextFileSchemaFile
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
            if (-not $SkipBackup) { Copy-Item -LiteralPath $file "$file$BackupSuffix" }
            $content | Set-Content -LiteralPath $file -Encoding $encoding -NoNewline
            $updated += 1
        }
        # (Get-Content -LiteralPath $file -Encoding $encoding) -replace $_.search, $_.replace | Set-Content -LiteralPath $file -Encoding $encoding
    }
    if ($updated -ge 1) {
        "File updated with new version string$(if ($updated -gt 1) { "s" })."
    }
    else {
        "No file updated needed."
    }
    "------------------------------"
}

$plugin_description_version_updater = Join-Path $PSScriptRoot "plugin-description-version-updater.py"
$python_arguments = @(
    $(if ($SkipBackup) { "--skip-backup" })
    "--backup-suffix"
    "$BackupSuffix"
    "$version"
    $PluginFiles
)
# python3 needs to be accessible from PATH!
python3.exe "$plugin_description_version_updater" $python_arguments
$python_exit_code = $LASTEXITCODE
if ($python_exit_code -ne 0) {
    throw "$plugin_description_version_updater failed. exit code: $python_exit_code"
}
