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


# serialize plugins via calling Spriggit

param (
    [string[]] $PluginNames = (Get-ChildItem -Path ".\data\*" -Include "*.esl", "*.esm", "*.esp" -File).Name,
    [switch] $JSON,
    [switch] $YAML,
    [switch] $Fallout4,
    [switch] $Starfield
)

# make sure to stop if an error happens
$ErrorActionPreference = "Stop"

# since parameter sets are a PITA in PowerShell, we'll just check manually
if (-not ($JSON -xor $YAML)) {
    throw "You must specify one of either JSON or YAML as the output format."
}
if (-not ($Fallout4 -xor $Starfield)) {
    throw "You must specify one of either Fallout 4 or Starfield as the game release."
}

$game_release = if ($Fallout4) { "Fallout4" } elseif ($Starfield) { "Starfield" }
$output_format = if ($YAML) { "Spriggit.Yaml" } elseif ($JSON) { "Spriggit.Json" }

# serialize each plugin individually
$PluginNames | ForEach-Object {
    $plugin_name = $_
    $spriggit_arguments = @(
        "serialize"
        "--InputPath"
        ".\data\$plugin_name"
        "--OutputPath"
        ".\spriggit\$plugin_name"
        "--GameRelease"
        $game_release
        "--PackageName"
        $output_format
        "--PackageVersion"
        "0.18.0"
    )
    & (Join-Path $PSScriptRoot "..\bin\SpriggitCLI\Spriggit.CLI.exe") $spriggit_arguments
}
