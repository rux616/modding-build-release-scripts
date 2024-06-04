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


# customizations for the archive manifests

# use these variables to add additional asset directories (must be of [AssetDirectory] type)
#
# examples:
#   $additional_asset_dirs = @([AssetDirectory]@{ Path = "foo_assets"; Compressible = $true; })
#   $additional_texture_dirs = @([AssetDirectory]@{ Path = "bar_textures"; Compressible = $true; })
$additional_asset_dirs = @()
$additional_texture_dirs = @()

# use these variables to add exclusions or inclusions (must be of [string] type, and inclusions override exclusions)
# strings can optionally be preceded with the following modifiers
#   - "literal:" to prevent wildcard expansion/regex matching
#   - "regex:" to use regex matching
#   - "wildcard:" to use wildcard matching
# additionally, unless prefixed, if a string contains "*", "?", or "[", it will be treated as a wildcard
# otherwise, strings will be treated as a literal string
# note: by default, 7z archives will exclude all asset directories, so you may need to include them explicitly
#
# examples:
#   $additional_exclude_all = @("foo.ini")
#   $additional_exclude_ba2 = @("bar\*.txt")
#   $additional_include_ba2 = @("regex:ba[rz]\\.*\.txt")
$additional_exclude_all = @()
$additional_exclude_ba2 = @()
$additional_include_ba2 = @()
$additional_exclude_7z = @()
$additional_include_7z = @()
