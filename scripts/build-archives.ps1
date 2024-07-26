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
    [string] $DataDir = ".\data",
    [string] $PluginName,
    [switch] $PutInDataSubdirectory,
    [switch] $IncludeBuildNumber,
    [switch] $PutInVersionSubdirectory,
    [string] $ManifestCustomizations = ".\support\scripts\archive-manifest-customizations.ps1",
    [Parameter(ParameterSetName = "Fallout 4", Mandatory)] [switch] $Fallout4,
    [Parameter(ParameterSetName = "Starfield", Mandatory)] [switch] $Starfield
)

# stop the script if an uncaught error happens
$ErrorActionPreference = "Stop"

# record the start time of the script for the purposes of creating unique temporary directories
$start_time = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")

# https://stackoverflow.com/a/34559554
function New-TemporaryDirectory {
    param([string] $Prefix)
    $parent = [System.IO.Path]::GetTempPath()
    [string] $name = [System.Guid]::NewGuid()
    if ($Prefix) { $name = $Prefix + "_" + $name }
    return New-Item -ItemType Directory -Path (Join-Path $parent $name)
}

function Join-Paths {
    param([Parameter(Mandatory, ValueFromRemainingArguments)] [string[]] $Paths)
    $final_path = $Paths[0]
    foreach ($path in $Paths[1..($Paths.Length - 1)]) {
        if (-not $path) { continue }
        $final_path = Join-Path $final_path $path
    }
    return $final_path
}

enum FilterType {
    Literal
    RegEx
    Wildcard
}

class ItemFilter : System.IEquatable[Object] {
    [string] $FilterString
    [FilterType] $FilterType

    [bool] Equals([Object] $obj) {
        if ($null -eq $obj) { return $false }
        if ($obj -isnot [ItemFilter]) { return $false }
        $other = [ItemFilter] $obj
        return $this.FilterString -eq $other.FilterString -and $this.FilterType -eq $other.FilterType
    }

    [string] ToString() { return "$($this.FilterType):$($this.FilterString)" }

    [bool] FilterStringContains([string[]] $Strings) {
        foreach ($string in $Strings) {
            if ($this.FilterString.Contains($string)) { return $true }
        }
        return $false
    }
}

class AssetDirectory : System.IEquatable[Object] {
    [string] $Path
    [bool] $Compressible

    AssetDirectory([hashtable] $Properties) {
        $this.Path = $Properties.Path
        $this.Compressible = $Properties.Compressible
    }

    [bool] Equals([Object] $obj) {
        if ($null -eq $obj) { return $false }
        if ($obj -isnot [AssetDirectory]) { return $false }

        $other = [AssetDirectory] $obj

        return $this.Path.Equals($other.Path) -and $this.Compressible.Equals($other.Compressible)
    }

    [string] ToString() { return "$($this.Path)" }
}

function Initialize-ItemFilters {
    [OutputType([System.Collections.Generic.HashSet[ItemFilter]])]
    param([string[]] $FilterStrings)

    $ignore_case = $true  # ignore case for the purposes of determining filter type
    $culture = $null  # use the current culture
    $to_return = [System.Collections.Generic.HashSet[ItemFilter]]::new()

    foreach ($filter_string in $FilterStrings) {
        if ($filter_string.StartsWith("$([FilterType]::RegEx):", $ignore_case, $culture)) {
            $filter_string = $filter_string.Substring($filter_string.IndexOf(":") + 1)
            $filter_type = [FilterType]::RegEx
        }
        elseif ($filter_string.StartsWith("$([FilterType]::Literal):", $ignore_case, $culture)) {
            $filter_string = $filter_string.Substring($filter_string.IndexOf(":") + 1)
            $filter_type = [FilterType]::Literal
        }
        elseif ($filter_string.StartsWith("$([FilterType]::Wildcard):", $ignore_case, $culture)) {
            $filter_string = $filter_string.Substring($filter_string.IndexOf(":") + 1)
            $filter_type = [FilterType]::Wildcard
        }
        elseif ((@("*", "?", "[") | Where-Object { $filter_string.Contains($_) }).Count -gt 0) {
            $filter_type = [FilterType]::Wildcard
        }
        else {
            $filter_type = [FilterType]::Literal
        }

        # remove leading ".\", "./", "\", or "/"
        if ($filter_string -match "^\.[\\/]+") { $filter_string = $filter_string.Substring(2) }
        elseif ($filter_string -match "^[\\/]+") { $filter_string = $filter_string.Substring(1) }

        if ($filter_string -eq "") { throw "Filter string is empty" }

        $to_return.Add(
            [ItemFilter]@{
                FilterString = $filter_string
                FilterType   = $filter_type
            }
        ) | Out-Null
    }

    return $to_return
}

function Invoke-ItemFilter {
    [OutputType([bool])]
    param (
        [string] $ItemPath,
        [string] $ItemName,
        [System.Collections.Generic.HashSet[ItemFilter]] $Filters
    )
    $directory_separators = @("\", "/")

    foreach ($filter in $Filters) {
        $comparison_string = if ($filter.FilterStringContains($directory_separators)) {
            $ItemPath
        }
        else {
            $ItemName
        }
        switch ($filter.FilterType) {
            ([FilterType]::Literal) { if ($comparison_string -eq $filter.FilterString) { return $true } }
            ([FilterType]::RegEx) { if ($comparison_string -match $filter.FilterString) { return $true } }
            ([FilterType]::Wildcard) { if ($comparison_string -like $filter.FilterString) { return $true } }
        }
    }

    return $false
}

function Get-FilteredItems {
    param (
        [string] $Path,
        [string] $BasePath,
        [System.Collections.Generic.HashSet[ItemFilter]] $ExcludeFilters,
        [System.Collections.Generic.HashSet[ItemFilter]] $IncludeFilters,
        [switch] $IncludeByDefault
    )

    $filtered_items = [System.Collections.Generic.List[string]]::new()
    $current_location = Get-Location
    Set-Location $BasePath

    try {
        $files = @(Get-ChildItem -Path $Path -File -Recurse)

        foreach ($file in $files) {
            $arguments = @{
                ItemPath = ($file | Resolve-Path -Relative).Substring(2)
                ItemName = $file.Name
            }

            $arguments.Filters = $IncludeFilters
            $explicit_include = Invoke-ItemFilter @arguments

            $exclude = if (-not $explicit_include) {
                $arguments.Filters = $ExcludeFilters
                Invoke-ItemFilter @arguments
            }
            else {
                $false
            }

            if ($exclude) { continue }
            else { $filtered_items.Add($arguments.ItemPath) | Out-Null }
        }
    }
    finally {
        Set-Location $current_location
    }

    return $filtered_items
}

function Copy-FilteredItems {
    param(
        [System.Collections.Generic.HashSet[AssetDirectory]] $AssetDirectories,
        [string] $DataDir = $DataDir,
        [string] $TempDir,
        [System.Collections.Generic.HashSet[ItemFilter]] $ExcludeFilters,
        [System.Collections.Generic.HashSet[ItemFilter]] $IncludeFilters,
        [switch] $PutInDataSubdirectory
    )

    $assets_found = $false
    $assets_compressible = $true

    foreach ($current_asset_dir in $AssetDirectories) {
        $get_filtered_items_params = @{
            Path           = $current_asset_dir
            BasePath       = $DataDir
            ExcludeFilters = $ExcludeFilters
            IncludeFilters = $IncludeFilters
        }
        $filtered_items = Get-FilteredItems @get_filtered_items_params

        if ($filtered_items.Count -gt 0) {
            $assets_found = $true
            if ($assets_compressible) { $assets_compressible = $current_asset_dir.Compressible }
            foreach ($item in $filtered_items) {
                $destination = Join-Paths @(
                    $TempDir
                    if ($PutInDataSubdirectory) { "data" }
                    $item
                )
                New-Item -Path (Split-Path -Path $destination) -ItemType Directory -Force | Out-Null
                Copy-Item -Path (Join-Path $DataDir $item) -Destination $destination
            }
        }
    }

    return $assets_found, $assets_compressible
}

enum ArchiveType {
    BA2
    SevenZip
}

function New-Archive {
    param(
        [string] $SourceDir,
        [string] $ArchiveName,
        [string] $Ba2Type,
        [switch] $Compressible,
        [ArchiveType] $ArchiveType
    )

    # remove existing archive
    if (Test-Path $ArchiveName) { Remove-Item -Force $ArchiveName }

    $current_location = Get-Location
    Set-Location $SourceDir

    try {
        switch ($ArchiveType) {
            ([ArchiveType]::BA2) {
                $arguments = @(
                    "pack"
                    ".\"
                    "$ArchiveName"
                    "-$Ba2Type"
                    if ($Compressible) { "-z" }
                    "-share"
                    "-mt"
                )
                BSArch64.exe $arguments
            }
            ([ArchiveType]::SevenZip) {
                $arguments = @(
                    "a"
                    "-t7z"
                    "-mx9"
                    "$ArchiveName"
                )
                7zr.exe $arguments
            }
        }
    }
    finally {
        Set-Location $current_location
    }
}

# source version class
. (Join-Path $PSScriptRoot "version-class.ps1")
# if the build number is to be included in the version, mark it as such
$version.IncludeBuildInVersionDefault = $IncludeBuildNumber

# archive type
$archive_type = if ($Fallout4) { "fo4" } elseif ($Starfield) { "sf1" }
$archive_type_dds = if ($Fallout4) { "fo4dds" } elseif ($Starfield) { "sf1dds" }

$ba2_base_name = if ($PluginName) { $PluginName } else { $ModName.Replace(" ", "") }
$local_dir = Get-Location
$build_dir = Join-Paths @(
    $local_dir
    "builds"
    if ($PutInVersionSubdirectory) { $version.ToString($false) }
)
$data_dir = Join-Path $local_dir "data"
$7z_file = Join-Path $build_dir ($ModName.Replace(" ", "_") + "-v" + $version + ".7z")

if (-not (Test-Path $build_dir)) {
    New-Item -ItemType Directory -Path $build_dir | Out-Null
}

$env:PATH = (Resolve-Path (Join-Path $PSScriptRoot "..\bin\BSArch")).Path + ";" + $env:PATH
$env:PATH = (Resolve-Path (Join-Path $PSScriptRoot "..\bin\7-Zip")).Path + ";" + $env:PATH

$temp_dir_general = New-TemporaryDirectory "build-archives_$($start_time)_general"
$temp_dir_textures = New-TemporaryDirectory "build-archives_$($start_time)_textures"
$temp_dir_7z = New-TemporaryDirectory "build-archives_$($start_time)_7z"
Write-Output "temp_dir_general: $temp_dir_general"
Write-Output "temp_dir_textures: $temp_dir_textures"
Write-Output "temp_dir_7z: $temp_dir_7z"
$ba2_archives_to_clean_up = [System.Collections.Generic.List[string]]::new()
try {
    # universal exclusions
    $exclude_all = [System.Collections.Generic.SortedSet[string]]@(
        "meta.ini"
    )

    # ba2 archive manifest
    $archive_manifest_ba2 = @{
        asset_dirs   = [System.Collections.Generic.HashSet[AssetDirectory]]@(
            [AssetDirectory]@{ Path = "distantlod"; Compressible = $true; }
            [AssetDirectory]@{ Path = "geometries"; Compressible = $true; }
            [AssetDirectory]@{ Path = "interface"; Compressible = $false; }
            [AssetDirectory]@{ Path = "lodsettings"; Compressible = $true; }
            [AssetDirectory]@{ Path = "materials"; Compressible = $true; }
            [AssetDirectory]@{ Path = "meshes"; Compressible = $true; }
            [AssetDirectory]@{ Path = "misc"; Compressible = $true; }
            [AssetDirectory]@{ Path = "particles"; Compressible = $true; }
            [AssetDirectory]@{ Path = "planetdata"; Compressible = $true; }
            [AssetDirectory]@{ Path = "scripts"; Compressible = $true; }
            [AssetDirectory]@{ Path = "shadersfx"; Compressible = $true; }
            [AssetDirectory]@{ Path = "sound"; Compressible = $false; }
            [AssetDirectory]@{ Path = "space"; Compressible = $true; }
            [AssetDirectory]@{ Path = "strings"; Compressible = $false; }
            [AssetDirectory]@{ Path = "terrain"; Compressible = $true; }
        )
        texture_dirs = [System.Collections.Generic.HashSet[AssetDirectory]]@(
            [AssetDirectory]@{ Path = "textures"; Compressible = $true; }
        )
        exclude      = [System.Collections.Generic.SortedSet[string]]@(
            "*.ini"
            "*.pas"
            "*.psc"
        )
        include      = [System.Collections.Generic.SortedSet[string]]@()
    }

    # 7z archive manifest
    $archive_manifest_7z = @{
        asset_dirs = [System.Collections.Generic.HashSet[AssetDirectory]]@(
            [AssetDirectory]@{ Path = "*"; Compressible = $true; }
        )
        exclude    = [System.Collections.Generic.SortedSet[string]]@(
            "*.pas"
        )
        include    = [System.Collections.Generic.SortedSet[string]]@()
    }

    # customizations
    if (Test-Path $ManifestCustomizations) {
        . $ManifestCustomizations
    }

    # powershell arrays are not compatible with UnionWith methods, so convert them to generic collections
    $additional_exclude_all = [System.Collections.Generic.List[string]] $additional_exclude_all
    $additional_asset_dirs = [System.Collections.Generic.List[AssetDirectory]] $additional_asset_dirs
    $additional_texture_dirs = [System.Collections.Generic.List[AssetDirectory]] $additional_texture_dirs
    $additional_exclude_ba2 = [System.Collections.Generic.List[string]] $additional_exclude_ba2
    $additional_include_ba2 = [System.Collections.Generic.List[string]] $additional_include_ba2
    $additional_exclude_7z = [System.Collections.Generic.List[string]] $additional_exclude_7z
    $additional_include_7z = [System.Collections.Generic.List[string]] $additional_include_7z

    # now that the arrays are generic collections, we can add them to the manifest
    if ($additional_exclude_all.Count) { $exclude_all.UnionWith($additional_exclude_all) }
    if ($additional_asset_dirs.Count) { $archive_manifest_ba2.asset_dirs.UnionWith($additional_asset_dirs) }
    if ($additional_texture_dirs.Count) { $archive_manifest_ba2.texture_dirs.UnionWith($additional_texture_dirs) }
    if ($additional_exclude_ba2.Count) { $archive_manifest_ba2.exclude.UnionWith($additional_exclude_ba2) }
    if ($additional_include_ba2.Count) { $archive_manifest_ba2.include.UnionWith($additional_include_ba2) }
    if ($additional_exclude_7z.Count) { $archive_manifest_7z.exclude.UnionWith($additional_exclude_7z) }
    if ($additional_include_7z.Count) { $archive_manifest_7z.include.UnionWith($additional_include_7z) }

    # now that the ba2 archive manifest is complete, we can add the asset directories to the 7z manifest exclusions
    foreach ($dir in $archive_manifest_ba2.asset_dirs) { [void] $archive_manifest_7z.exclude.Add($dir.Path + "\*") }
    foreach ($dir in $archive_manifest_ba2.texture_dirs) { [void] $archive_manifest_7z.exclude.Add($dir.Path + "\*") }

    # combine exclude_all with the other exclude sets
    $archive_manifest_ba2.exclude.UnionWith($exclude_all)
    $archive_manifest_7z.exclude.UnionWith($exclude_all)

    # convert exclusions and inclusions to hash sets of ItemFilter objects
    $archive_manifest_ba2.exclude = Initialize-ItemFilters $archive_manifest_ba2.exclude
    $archive_manifest_ba2.include = Initialize-ItemFilters $archive_manifest_ba2.include
    $archive_manifest_7z.exclude = Initialize-ItemFilters $archive_manifest_7z.exclude
    $archive_manifest_7z.include = Initialize-ItemFilters $archive_manifest_7z.include

    # copy assets to be put in a general BA2 to a temporary directory
    $arguments = @{
        AssetDirectories = $archive_manifest_ba2.asset_dirs
        DataDir          = $DataDir
        TempDir          = $temp_dir_general
        ExcludeFilters   = $archive_manifest_ba2.exclude
        IncludeFilters   = $archive_manifest_ba2.include
    }
    $assets_found, $assets_compressible = Copy-FilteredItems @arguments
    # create general BA2
    $arguments = @{
        SourceDir    = $temp_dir_general
        ArchiveType  = [ArchiveType]::BA2
        ArchiveName  = Join-Path $data_dir "$ba2_base_name - Main.ba2"
        Ba2Type      = $archive_type
        Compressible = $assets_compressible
    }
    if ($assets_found) {
        New-Archive @arguments
        $ba2_archives_to_clean_up.Add($arguments.ArchiveName)
    }

    # copy assets to be put in a texture BA2 to a temporary directory
    $arguments = @{
        AssetDirectories = $archive_manifest_ba2.texture_dirs
        DataDir          = $DataDir
        TempDir          = $temp_dir_textures
        ExcludeFilters   = $archive_manifest_ba2.exclude
        IncludeFilters   = $archive_manifest_ba2.include
    }
    $assets_found, $assets_compressible = Copy-FilteredItems @arguments
    # create texture BA2
    $arguments = @{
        SourceDir    = $temp_dir_textures
        ArchiveType  = [ArchiveType]::BA2
        ArchiveName  = Join-Path $data_dir "$ba2_base_name - Textures.ba2"
        Ba2Type      = $archive_type_dds
        Compressible = $assets_compressible
    }
    if ($assets_found) {
        New-Archive @arguments
        $ba2_archives_to_clean_up.Add($arguments.ArchiveName)
    }

    # copy assets to be put in a 7z to a temporary directory
    $arguments = @{
        AssetDirectories = $archive_manifest_7z.asset_dirs
        DataDir          = $DataDir
        TempDir          = $temp_dir_7z
        ExcludeFilters   = $archive_manifest_7z.exclude
        IncludeFilters   = $archive_manifest_7z.include
    }
    $assets_found, $assets_compressible = Copy-FilteredItems @arguments
    # create 7z
    $arguments = @{
        SourceDir   = $temp_dir_7z
        ArchiveType = [ArchiveType]::SevenZip
        ArchiveName = $7z_file
    }
    if ($assets_found) { New-Archive @arguments }
}
catch {
    $error_message = @(
        "$($_.Exception.Message)`n"
        "$($_.InvocationInfo.PositionMessage)`n"
        "    + CategoryInfo          : $($_.CategoryInfo)`n"
        "    + FullyQualifiedErrorId : $($_.FullyQualifiedErrorId)`n"
    )
    Write-Host -Foreground Red -Background Black $error_message
}
finally {
    Remove-Item -Force -Recurse -Path $temp_dir_general
    Remove-Item -Force -Recurse -Path $temp_dir_textures
    Remove-Item -Force -Recurse -Path $temp_dir_7z
    $ba2_archives_to_clean_up | ForEach-Object { if ((Test-Path $_)) { Remove-Item -Force $_ } }
}
