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


# example of a map of GitHub in-repo image URLs to Nexus Mods image URLs, for use in the markdown-to-nexusbbcode script

# the keys should be the GitHub in-repo file paths, and the values should be the corresponding Nexus Mods URLs
$nexus_image_map = @{
    "./support/packaging/foo.jpg" = "https://staticdelivery.nexusmods.com/mods/0000/images/000/000-0000000000-000000000.jpg"
    "./support/packaging/bar.jpg" = "https://staticdelivery.nexusmods.com/mods/0000/images/000/000-0000000000-000000001.jpg"
}
