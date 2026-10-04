"""Update the single-app SideStore source after publishing the matching IPA."""

import datetime
import json
import os
import plistlib
import sys
from pathlib import Path
from zipfile import ZipFile


ipa = Path(sys.argv[1])
run_number = sys.argv[2]
tag = f"ios-build-{run_number}"
repository = os.environ.get("GITHUB_REPOSITORY", "matvada/BAT-TV")
base = f"https://github.com/{repository}"
raw = f"https://raw.githubusercontent.com/{repository}/main"

with ZipFile(ipa) as archive:
    info = plistlib.loads(archive.read("Payload/BAT tv.app/Info.plist"))

version = info["CFBundleShortVersionString"]
build = info["CFBundleVersion"]
bundle_id = info["CFBundleIdentifier"]
if (str(build) != run_number or str(version) != f"1.0.{run_number}"
        or bundle_id != "it.courtside.camera"):
    raise SystemExit("IPA version or bundle ID differs from expected build")
if ipa.name != f"BAT-tv-{version}-iPhone-SideStore.ipa":
    raise SystemExit("IPA filename differs from expected version")

source = {
    "name": "BAT tv",
    "identifier": "it.courtside.camera.source",
    "sourceURL": f"{raw}/altstore.json",
    "apps": [
        {
            "name": "BAT tv",
            "bundleIdentifier": bundle_id,
            "developerName": "BAT tv",
            "localizedDescription": "Diretta basket con Camera, Regia e Punteggi via Bluetooth.",
            "iconURL": f"{raw}/iPhone/COURTSIDE/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
            "tintColor": "#512A7D",
            "versions": [
                {
                    "version": str(version),
                    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "downloadURL": f"{base}/releases/download/{tag}/{ipa.name}",
                    "size": ipa.stat().st_size,
                    "minOSVersion": "17.0",
                }
            ],
        }
    ],
}
Path("altstore.json").write_text(json.dumps(source, indent=2, ensure_ascii=False) + "\n")
print(f"SideStore source updated for {version} ({build})")
