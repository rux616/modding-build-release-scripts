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
    [string] $DataFolder,
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
$spriggit_exe_name = "Spriggit.CLI.exe"
$spriggit_exe = Join-Path $spriggit_dir $spriggit_exe_name
$spriggit_zip_name = "SpriggitCLI.zip"
$spriggit_zip = Join-Path $spriggit_dir $spriggit_zip_name
$spriggit_cache_name = "spriggit.cache"
$spriggit_cache = Join-Path $spriggit_dir $spriggit_cache_name

# read cache file if it exists
if (Test-Path (Join-Path $PSScriptRoot $spriggit_cache)) {
    $cache = Get-Content (Join-Path $PSScriptRoot $spriggit_cache) | ConvertFrom-Json -AsHashtable
}
$cache_new = [ordered]@{}

# check if things need to be totally re-serialized
$cache_new.$spriggit_zip_name = (Get-FileHash -Algorithm MD5 -Path (Join-Path $PSScriptRoot $spriggit_zip)).Hash
$cache_new."DataFolder" = $DataFolder
if (`
    (-not (Test-Path (Join-Path $PSScriptRoot $spriggit_exe))) -or `
    ($cache.$spriggit_zip_name -ne $cache_new.$spriggit_zip_name) -or `
    ($cache."DataFolder" -ne $cache_new."DataFolder") `
) {
    if (-not (Test-Path (Join-Path $PSScriptRoot $spriggit_exe))) {
        Write-Host -ForegroundColor Yellow -BackgroundColor Black "$spriggit_exe_name not found. Unpacking archive."
    }
    elseif (-not (Test-Path (Join-Path $PSScriptRoot $spriggit_cache))) {
        Write-Host -ForegroundColor Yellow -BackgroundColor Black "Existing cache file not found. Performing full serialization."
    }
    elseif ($cache.$spriggit_zip_name -ne $cache_new.$spriggit_zip_name) {
        Write-Host -ForegroundColor Yellow -BackgroundColor Black "$spriggit_zip_name hash has changed (cache: $($cache.$spriggit_zip_name), file: $($cache_new.$spriggit_zip_name)). Invalidating cache, deleting old files, and unpacking new archive."
        $cache = @{}
    }
    elseif ($cache."DataFolder" -ne $DataFolder) {
        Write-Host -ForegroundColor Yellow -BackgroundColor Black "DataFolder has changed (cache: `"$($cache."DataFolder")`", given: `"$DataFolder`"). Invalidating cache and re-serializing plugins."
        $cache = @{}
    }

    Get-ChildItem -Path (Join-Path $PSScriptRoot $spriggit_dir)`
    | Where-Object { -not ($_.Name -in @($spriggit_zip_name, ".gitignore", "spriggit.cache")) } `
    | Remove-Item -Recurse -Force
    Expand-Archive -Path (Join-Path $PSScriptRoot $spriggit_zip) -DestinationPath (Join-Path $PSScriptRoot $spriggit_dir)
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
        $script:cache_new.$plugin_name = (Get-FileHash -Algorithm MD5 -Path ".\data\$plugin_name").Hash
        if ($cache.$plugin_name -eq $script:cache_new.$plugin_name) {
            Write-Host -ForegroundColor Yellow -BackgroundColor Black "Skipping plugin $plugin_name because it hasn't changed."
            return
        }
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
            "0.26.0"
            if ($DataFolder) { "--DataFolder" }
            if ($DataFolder) { $DataFolder }
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

# write cache file
if (-not $spriggit_error) {
    $cache_new | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot $spriggit_cache)
}

exit $spriggit_error
