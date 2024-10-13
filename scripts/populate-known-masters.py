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


# write known masters to a .spriggit file


import argparse
import enum
import json
import sys


class MasterType(str, enum.Enum):
    FULL = "Full"
    MEDIUM = "Medium"
    SMALL = "Small"


class Master(dict):
    def __init__(self, name: str, type: MasterType):
        dict.__init__(self, ModKey=name, Style=type)
        self.name = self["ModKey"]
        self.type = self["Style"]

    def __hash__(self):
        return hash(self.name)

    def __eq__(self, other):
        return self.name == other.name


def main(
    full_masters: list[str], medium_masters: list[str], small_masters: list[str], spriggit_file: str, sort_by: str
) -> int:
    known_masters = set(
        [
            # base game + patches as of v1.14.70.0
            Master("Starfield.esm", MasterType.FULL),
            Master("SFBGS003.esm", MasterType.MEDIUM),
            Master("SFBGS004.esm", MasterType.SMALL),
            Master("SFBGS006.esm", MasterType.MEDIUM),
            Master("SFBGS007.esm", MasterType.SMALL),
            Master("SFBGS008.esm", MasterType.SMALL),
            Master("BlueprintShips-Starfield.esm", MasterType.FULL),
            # pre-release content
            Master("Constellation.esm", MasterType.SMALL),
            Master("OldMars.esm", MasterType.SMALL),
            # DLC
            Master("ShatteredSpace.esm", MasterType.FULL),
        ]
    )

    for master_list, master_type in (
        (full_masters, MasterType.FULL),
        (medium_masters, MasterType.MEDIUM),
        (small_masters, MasterType.SMALL),
    ):
        for master_file in master_list:
            known_master_size_old = len(known_masters)
            known_masters.add(Master(master_file, master_type))
            if known_master_size_old == len(known_masters):
                print(f"[WARNING] Duplicate master: {master_file}")

    # read an existing spriggit file if one exists so as to get any existing settings
    try:
        spriggit_file_content = json.load(open(spriggit_file, "r"))
    except FileNotFoundError:
        spriggit_file_content = {}

    spriggit_file_content["KnownMasters"] = [master for master in known_masters]
    match sort_by:
        case "name":
            spriggit_file_content["KnownMasters"].sort(key=lambda master: master.name.lower())
        case "type":
            spriggit_file_content["KnownMasters"].sort(key=lambda master: (master.type.lower(), master.name.lower()))

    with open(spriggit_file, "w") as f:
        json.dump(spriggit_file_content, f, indent=2)

    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Populate known masters")

    parser.add_argument("--full-masters", help="List of full masters", nargs="+", metavar="MASTER", default=[])
    parser.add_argument("--medium-masters", help="List of medium masters", nargs="+", metavar="MASTER", default=[])
    parser.add_argument("--small-masters", help="List of small masters", nargs="+", metavar="MASTER", default=[])
    parser.add_argument("--spriggit-file", help="Path to spriggit file", default="./spriggit/.spriggit", metavar="FILE")
    parser.add_argument("--sort-by", help="Sort by", choices=["name", "type"], default="name")

    args = parser.parse_args()

    sys.exit(main(args.full_masters, args.medium_masters, args.small_masters, args.spriggit_file, args.sort_by))
