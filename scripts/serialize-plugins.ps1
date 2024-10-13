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
    [string] $PluginFolder = ".\data",
    [string[]] $PluginNames = (Get-ChildItem -Path "$PluginFolder\*" -Include "*.esl", "*.esm", "*.esp" -File).Name,
    [string] $OutputFolder = ".\spriggit",
    [string] $PackageVersion = "match",
    [string] $DataFolder = "",
    [string] $CacheFile = "spriggit.cache",
    [switch] $JSON,
    [switch] $YAML,
    [switch] $Fallout4,
    [switch] $Starfield,
    [switch] $Force
)

enum GameRelease {
    Fallout4
    Starfield
}

enum OutputFormat {
    Json
    Yaml
}

# make sure to stop if an error happens
$ErrorActionPreference = "Stop"

# since parameter sets are a PITA in PowerShell, we'll just check manually
if (-not ($JSON -xor $YAML)) {
    throw "You must specify one of either JSON or YAML as the output format."
}
if (-not ($Fallout4 -xor $Starfield)) {
    throw "You must specify one of either Fallout 4 or Starfield as the game release."
}

$game_release = if ($Fallout4) { [GameRelease]::Fallout4 } elseif ($Starfield) { [GameRelease]::Starfield }
$output_format = if ($YAML) { [OutputFormat]::Yaml } elseif ($JSON) { [OutputFormat]::Json }

if ($null -eq $PluginNames -or $PluginNames.Count -eq 0) {
    throw "No plugins found to serialize."
}

# define paths
$spriggit_dir = "..\bin\SpriggitCLI"
$spriggit_exe_name = "Spriggit.CLI.exe"
$spriggit_exe = Join-Path $spriggit_dir $spriggit_exe_name
$spriggit_zip_name = (Get-ChildItem -Path (Join-Path $PSScriptRoot $spriggit_dir) -Filter "SpriggitCLI-v*.zip").Name
$spriggit_zip = Join-Path $spriggit_dir $spriggit_zip_name
$spriggit_cache_name = $CacheFile
$spriggit_cache = Join-Path $spriggit_dir $spriggit_cache_name

switch ($PackageVersion) {
    # if PackageVersion is "match", get the version from the Spriggit CLI zip filename
    "match" {
        $PackageVersion = [System.IO.Path]::GetFileNameWithoutExtension($spriggit_zip_name) -replace "SpriggitCLI-v", ""
        if ($null -eq $PackageVersion) {
            throw "Failed to get the version from the Spriggit CLI zip filename."
        }
        Write-Host -ForegroundColor Yellow -BackgroundColor Black "Using Spriggit package version from zip filename: $PackageVersion"
    }
    # if PackageVersion is "latest", get the latest version from NuGet
    "latest" {
        $nuget_url = "https://api.nuget.org/v3-flatcontainer/spriggit.$($output_format.ToString().ToLower()).$($game_release.ToString().ToLower())/index.json"
        $PackageVersion = ((Invoke-RestMethod -Uri $nuget_url).versions -match "^\d+\.\d+\.\d+$")[-1]
        if ($null -eq $PackageVersion) {
            throw "Failed to get the latest version of Spriggit from NuGet."
        }
        Write-Host -ForegroundColor Yellow -BackgroundColor Black "Using latest Spriggit package version from NuGet: $PackageVersion"
    }
}

# read cache file if it exists
if (Test-Path (Join-Path $PSScriptRoot $spriggit_cache)) {
    $cache = Get-Content (Join-Path $PSScriptRoot $spriggit_cache) | ConvertFrom-Json -AsHashtable
}
$cache_new = [ordered]@{}

# check if things need to be totally re-serialized
$cache_new.$spriggit_zip_name = (Get-FileHash -Algorithm MD5 -Path (Join-Path $PSScriptRoot $spriggit_zip)).Hash
$cache_new."PackageVersion" = $PackageVersion
$cache_new."DataFolder" = $DataFolder
$cache_new."PluginFolder" = $PluginFolder
$unpack_archive = $false
if ($Force) {
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "Forcing full serialization."
    $cache = @{}
    $unpack_archive = $true
}
elseif (-not (Test-Path (Join-Path $PSScriptRoot $spriggit_exe))) {
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "$spriggit_exe_name not found. Unpacking archive."
    $unpack_archive = $true
}
elseif (-not (Test-Path (Join-Path $PSScriptRoot $spriggit_cache))) {
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "Existing cache file not found. Performing full serialization."
    $unpack_archive = $true
}
elseif ($cache.$spriggit_zip_name -ne $cache_new.$spriggit_zip_name) {
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "$spriggit_zip_name hash has changed (cache: $($cache.$spriggit_zip_name), file: $($cache_new.$spriggit_zip_name)). Invalidating cache, deleting old files, and unpacking new archive."
    $cache = @{}
    $unpack_archive = $true
}
elseif ($cache."PackageVersion" -ne $cache_new."PackageVersion") {
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "PackageVersion has changed (cache: `"$($cache."PackageVersion")`", given: `"$($cache_new."PackageVersion")`"). Invalidating cache and re-serializing plugins."
    $cache = @{}
    $unpack_archive = $true
}
elseif ($cache."DataFolder" -ne $cache_new."DataFolder") {
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "DataFolder has changed (cache: `"$($cache."DataFolder")`", given: `"$($cache_new."DataFolder")`"). Invalidating cache and re-serializing plugins."
    $cache = @{}
    $unpack_archive = $true
}
elseif ($cache."PluginFolder" -ne $cache_new."PluginFolder") {
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "PluginFolder has changed (cache: `"$($cache."PluginFolder")`", given: `"$($cache_new."PluginFolder")`"). Invalidating cache and re-serializing plugins."
    $cache = @{}
    $unpack_archive = $true
}

# if needed, clear out the existing spriggit binaries and unpack the archive
if ($unpack_archive) {
    $allowed_files = @($spriggit_zip_name, ".gitignore", $CacheFile)
    Get-ChildItem -Path (Join-Path $PSScriptRoot $spriggit_dir) `
    | Where-Object { ($_.Name -notin $allowed_files) -and ($_.Name -notlike "*.cache") } `
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
        $script:cache_new.$plugin_name = (Get-FileHash -Algorithm MD5 -Path "$PluginFolder\$plugin_name").Hash
        if ($cache.$plugin_name -eq $script:cache_new.$plugin_name) {
            Write-Host -ForegroundColor Yellow -BackgroundColor Black "Skipping plugin $plugin_name because it hasn't changed."
            return
        }
        $spriggit_arguments = @(
            "serialize"
            "--InputPath"
            "$PluginFolder\$plugin_name"
            "--OutputPath"
            "$OutputFolder\$plugin_name"
            "--GameRelease"
            $game_release
            "--PackageName"
            "Spriggit.$output_format"
            "--PackageVersion"
            $PackageVersion
            if ($DataFolder -or $game_release -eq [GameRelease]::Starfield) { "--DataFolder" }
            if ($DataFolder -or $game_release -eq [GameRelease]::Starfield) { $DataFolder }
        )
        & (Join-Path $PSScriptRoot $spriggit_exe) $spriggit_arguments
        if ($LASTEXITCODE -ne 0) {
            Write-Host -ForegroundColor Red -BackgroundColor Black "Failed to serialize plugin $plugin_name."
            $script:spriggit_error = $true
            return
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
