# Copyright 2024 Dan Cassidy

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


# generate a batch processor script for xTranslator

param (
    [string[]] $PluginFiles = (Get-ChildItem -Path ".\data\*" -Include "*.esl", "*.esm", "*.esp" -File).Name,
    [string] $OutputFile = ".\support\scripts\xTranslator-BatchProcessor.txt"
)

$ErrorActionPreference = "Stop"

$language_source = "en"
$language_destinations = @(
    "de"
    "es"
    "fr"
    "it"
    "ja"
    "pl"
    "ptbr"
    "zhhans"
)

if (-not (Test-Path -LiteralPath $OutputFile)) { New-Item $OutputFile | Out-Null }
$file_out = Get-Item -LiteralPath $OutputFile

$content = ""

$PluginFiles | ForEach-Object {
    $plugin_file_name = $_
    $plugin_name = $plugin_file_name.Substring(0, $plugin_file_name.Length - 4)

    $language_destinations | ForEach-Object {
        $language_dest = $_

        $content += @(
            "StartRule"
            "LangSource=$language_source"
            "LangDest=$language_dest"
            "UseDataDir=1"
            "Command=LoadFile:$plugin_file_name"
            "Command=ApplySst:0:1:$plugin_name"
            "Command=ApiTranslation:5:1"
            "Command=Finalize"
            "Command=SaveDictionary"
            "Command=CloseAll"
            "EndRule"
            ""
            ""
        ) -join "`r`n"
    }
}

$content | Set-Content -LiteralPath $file_out -NoNewline
