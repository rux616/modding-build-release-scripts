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


# build archives

param (
    [Parameter(Mandatory)] [string] $ModName,
    [string] $PluginName,
    [switch] $PutInDataSubdirectory,
    [switch] $IncludeBuildNumber,
    [switch] $PutInVersionSubdirectory,
    [string[]] $Exclude,
    [Parameter(ParameterSetName = "Fallout 4", Mandatory)] [switch] $Fallout4,
    [Parameter(ParameterSetName = "Starfield", Mandatory)] [switch] $Starfield
)

# https://stackoverflow.com/a/34559554
function New-TemporaryDirectory {
    $parent = [System.IO.Path]::GetTempPath()
    [string] $name = [System.Guid]::NewGuid()
    New-Item -ItemType Directory -Path (Join-Path $parent $name) | Out-Null
}

# stop the script if an uncaught error happens
$ErrorActionPreference = "Stop"

# source version class
. (Join-Path $PSScriptRoot "version-class.ps1")
# if the build number is to be included in the version, mark it as such
$version.IncludeBuildInVersionDefault = $IncludeBuildNumber

# archive type
$archive_type = if ($Fallout4) { "fo4" } elseif ($Starfield) { "sf1" }
$archive_type_dds = if ($Fallout4) { "fo4dds" } elseif ($Starfield) { "sf1dds" }

$ba2_base_name = if ($PluginName) { $PluginName } else { $ModName.Replace(" ", "") }
$local_dir = Get-Location
$build_dir = Join-Path $local_dir "builds" $(if ($PutInVersionSubdirectory) { $version.ToString($false) })
$data_dir = Join-Path $local_dir "data"
$7z_file = Join-Path $build_dir ($ModName.Replace(" ", "_") + "-v" + $version + ".7z")

if (-not (Test-Path $build_dir)) {
    New-Item -ItemType Directory -Path $build_dir | Out-Null
}

$bsarch_exe = Join-Path $PSScriptRoot "..\bin\BSArch\BSArch64.exe"
$7z_exe = Join-Path $PSScriptRoot "..\bin\7-Zip\7zr.exe"

$temp_dir_general = New-TemporaryDirectory
$temp_dir_textures = New-TemporaryDirectory
$ba2_archives_to_remove = [System.Collections.Generic.List[string]]::new()
try {
    # excluded files
    $excluded_files = @(
        "*.psc"
        "*.*sonnet"
        "*.ppj"
    ) + $Exclude
    # potential directories to put into general BA2s:
    $asset_dirs = @(
        "distantlod"
        "geometries"
        "interface"
        "lodsettings"
        "materials"
        "meshes"
        "misc"
        "particles"
        "planetdata"
        "scripts"
        "shadersfx"
        "sound"
        "space"
        "strings"
        "terrain"
    )
    # if these directories are present, an archive becomes non-compressible
    $non_compressible_asset_dirs = @(
        "interface"
        "sound"
        "strings"
    )
    # copy stuff to be put in a general BA2 to a temporary directory
    $assets_found = $false
    $assets_compressible = $true
    $asset_dirs | ForEach-Object {
        $current_asset_dir = Join-Path "data" $_
        if (Test-Path $current_asset_dir) {
            $script:assets_found = $true
            if ($non_compressible_asset_dirs -contains $_) {
                $script:assets_compressible = $false
            }
            $copy_item_params = @{
                Recurse     = $true
                Path        = $current_asset_dir
                Destination = $temp_dir_general
                Exclude     = $excluded_files
            }
            Copy-Item @copy_item_params
        }
    }
    # make general BA2
    If ($assets_found) {
        & $bsarch_exe `
            pack `
            "$temp_dir_general" `
            "$data_dir\$ba2_base_name - Main.ba2" `
            -$archive_type `
            "$(if ($assets_compressible) { "-z" } else {})" `
            -share `
            -mt
        $ba2_archives_to_remove.Add("$data_dir\$ba2_base_name - Main.ba2")
    }

    # potential directories to put into texture BA2s:
    $texture_dirs = @(
        "textures"
    )
    # copy stuff to be put in a texture BA2 to a temporary directory
    $assets_found = $false
    $texture_dirs | ForEach-Object {
        $current_asset_dir = Join-Path "data" $_
        if (Test-Path $current_asset_dir) {
            $script:assets_found = $true
            $copy_item_params = @{
                Recurse     = $true
                Path        = $current_asset_dir
                Destination = $temp_dir_textures
                Exclude     = $excluded_files
            }
            Copy-Item @copy_item_params
        }
    }
    # make texture BA2
    if ($assets_found) {
        & $bsarch_exe `
            pack `
            "$temp_dir_textures" `
            "$data_dir\$ba2_base_name - Textures.ba2" `
            -$archive_type_dds `
            -z `
            -share `
            -mt
        $ba2_archives_to_remove.Add("$data_dir\$ba2_base_name - Textures.ba2")
    }

    # create exclusion file for 7z
    $content = @("meta.ini") + $excluded_files + $asset_dirs + $texture_dirs | ForEach-Object {
        if ($PutInDataSubdirectory) {
            Join-Path "data" $_
        }
        else {
            $_
        }
    }
    $7z_exclude_file = Join-Path $temp_dir_general "7z-exclude.txt"
    Write-Output "7z_exclude_file = $7z_exclude_file"
    Set-Content -Path $7z_exclude_file -Value $content
    # make 7z
    if (Test-Path $7z_file) { Remove-Item -Force $7z_file }
    $7z_params = @(
        "a"
        "-t7z"
        "-mx9"
        $7z_file
        if ($PutInDataSubdirectory) { ".\data" } else { "." }
        "-xr@$7z_exclude_file"
    )
    if ($PutInDataSubdirectory) {
        & $7z_exe $7z_params
    }
    else {
        $working_dir = Get-Location
        Set-Location $data_dir
        & $7z_exe $7z_params
        Set-Location $working_dir
    }
}
finally {
    Write-Output "temp_dir_general: $temp_dir_general"
    Write-Output "temp_dir_textures: $temp_dir_textures"
    Remove-Item -Force -Recurse -Path $temp_dir_general
    Remove-Item -Force -Recurse -Path $temp_dir_textures
    Remove-Item -Force $ba2_archives_to_remove
}
