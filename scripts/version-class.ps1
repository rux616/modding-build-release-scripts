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


# contains the version class

# source the actual version info - expects '.' to be the root of the project
. (Join-Path (Get-Location) ".version.ps1")

class Version {
    ### PROPERTIES
    # version info
    [int] $VersionMajor = $version_major
    [int] $VersionMinor = $version_minor
    [int] $VersionPatch = $version_patch

    # prerelease info
    [int] $VersionPrerelease = $version_prerelease
    [bool] $IsPrerelease = $is_pre
    [bool] $IsReleaseCandidate = $is_rc
    [bool] $IsBeta = $is_beta
    [bool] $IsAlpha = $is_alpha

    # build info
    [int] $BuildNumber = $build_number
    [bool] $IncludeBuildInVersionDefault = $include_build_in_version


    ### METHODS
    [void] IncrementBuild() {
        $this.BuildNumber += 1
    }

    [string] ToString() {
        return $this.ToString($this.IncludeBuildInVersionDefault)
    }

    [string] ToString([bool] $WithBuild) {
        # check to see if this is a pre-release
        if ($this.IsPrerelease) {
            [string] $prerelease_classification = "pre"
        }
        elseif ($this.IsReleaseCandidate) {
            [string] $prerelease_classification = "rc"
        }
        elseif ($this.IsBeta) {
            [string] $prerelease_classification = "beta"
        }
        elseif ($this.IsAlpha) {
            [string] $prerelease_classification = "alpha"
        }
        else {
            [string] $prerelease_classification = ""
        }

        # build the version strings
        [string] $version = (
            $this.VersionMajor.ToString() + "." +
            $this.VersionMinor.ToString() + "." +
            $this.VersionPatch.ToString()
        )
        if ($prerelease_classification) {
            $version += "-$prerelease_classification"
            if ($this.VersionPrerelease) {
                $version += "." + $this.VersionPrerelease.ToString()
            }
        }
        if ($WithBuild) {
            return $version + "+" + $this.BuildNumber.ToString()
        }
        else {
            return $version
        }
    }
}

$version = [Version]::new()
