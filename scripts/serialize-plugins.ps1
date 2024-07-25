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
$output_format = if ($YAML) { "Yaml" } elseif ($JSON) { "Json" }

$spriggit_dir = "..\bin\SpriggitCLI"
$spriggit_exe = Join-Path $spriggit_dir "Spriggit.CLI.exe"
$spriggit_zip = Join-Path $spriggit_dir "SpriggitCLI.zip"

# unpack SpriggitCLI if it hasn't been unpacked yet
if (-not (Test-Path (Join-Path $PSScriptRoot $spriggit_exe))) {
    Expand-Archive -Path $spriggit_zip -DestinationPath (Join-Path $PSScriptRoot $spriggit_dir)
}

$spriggit_error = $null
foreach ($i in 1..2) {
    if ($null -eq $spriggit_error) {
        # do nothing, loop hasn't run yet
        [void] 'noop'
    }
    elseif ($spriggit_error -eq $false) {
        # loop ran successfully
        break
    }
    elseif ($spriggit_error -eq $true) {
        # first loop iteration failed, delete spriggit's temp folder and try again
        $arguments = @{
            ForegroundColor = [System.ConsoleColor]::Red
            BackgroundColor = [System.ConsoleColor]::Black
            Object          = "Failed to serialize plugins. Deleting Spriggit temp folder and trying again."
        }
        Write-Host @arguments
        $spriggit_temp_folder = Join-Path ([System.IO.Path]::GetTempPath()) "Spriggit"
        if ((Test-Path $spriggit_temp_folder)) {
            Remove-Item -Path $spriggit_temp_folder -Recurse -Force
            $spriggit_error = $null
        }
        else {
            Write-Host -ForegroundColor Red -BackgroundColor Black "Failed to find Spriggit temp folder to delete."
            break
        }
    }
    else {
        throw "Unexpected value for spriggit_error (how?!?): $spriggit_error"
    }

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
            "Spriggit.$output_format"
            "--PackageVersion"
            "0.25.0"
        )
        & (Join-Path $PSScriptRoot $spriggit_exe) $spriggit_arguments
        if ($LASTEXITCODE -ne 0) {
            Write-Host -ForegroundColor Red -BackgroundColor Black "Failed to serialize plugin $plugin_name."
            $script:spriggit_error = $true
        }
        else {
            Write-Host -ForegroundColor Green -BackgroundColor Black "Successfully serialized plugin $plugin_name."
        }
    }

    # if spriggit ran successfully, $spriggit_error will still be null, so set it to false
    if ($null -eq $spriggit_error) {
        $spriggit_error = $false
        Write-Host -ForegroundColor Green -BackgroundColor Black "Successfully serialized all plugins."
        break
    }
}

exit $spriggit_error
