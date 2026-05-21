#!/bin/zsh
# Updates appcast.xml with a new release entry.
#
# Usage:
#   zsh scripts/update-appcast.sh <version> <build_number> <ed_signature> <length> [pub_date]
#
# Example:
#   zsh scripts/update-appcast.sh 1.0.3 970 "abc123==" 9014852
#
# If pub_date is omitted, the current UTC time is used.

set -euo pipefail

if [[ $# -lt 4 ]]; then
    echo "Usage: $0 <version> <build_number> <ed_signature> <length> [pub_date]" >&2
    exit 1
fi

VERSION="$1"
BUILD_NUMBER="$2"
ED_SIGNATURE="$3"
LENGTH="$4"
PUB_DATE="${5:-$(date -u '+%a, %d %b %Y %H:%M:%S +0000')}"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
appcast="$repo_root/appcast.xml"

if [[ ! -f "$appcast" ]]; then
    echo "Error: appcast.xml not found at $appcast" >&2
    exit 1
fi

release_repo="${ATOLL_RELEASE_REPO:-h4ckm1n-dev/atoll}"
release_asset="${ATOLL_RELEASE_ASSET_NAME:-Atoll.zip}"
download_url="https://github.com/${release_repo}/releases/download/v${VERSION}/${release_asset}"

# Use Python for reliable XML-adjacent text insertion
python3 - "$appcast" "$VERSION" "$BUILD_NUMBER" "$ED_SIGNATURE" "$LENGTH" "$PUB_DATE" "$download_url" <<'PYEOF'
import sys

appcast_path = sys.argv[1]
version = sys.argv[2]
build_number = sys.argv[3]
ed_signature = sys.argv[4]
length = sys.argv[5]
pub_date = sys.argv[6]
download_url = sys.argv[7]

new_item = f"""        <item>
            <title>Version {version}</title>
            <sparkle:version>{build_number}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <pubDate>{pub_date}</pubDate>
            <enclosure
                url="{download_url}"
                type="application/octet-stream"
                sparkle:edSignature="{ed_signature}"
                length="{length}"
            />
        </item>"""

with open(appcast_path, "r") as f:
    content = f.read()

marker = "<!-- Items are added by the release workflow. See docs/releasing.md. -->"
if marker not in content:
    print("Error: marker comment not found in appcast.xml", file=sys.stderr)
    sys.exit(1)

# Keep the script idempotent so a failed release run can safely re-run and
# replace the same version's item instead of stacking duplicate entries.
import re
escaped_version = re.escape(version)
content = re.sub(
    rf"\n        <item>\n(?:(?!        <item>).)*?<sparkle:shortVersionString>{escaped_version}</sparkle:shortVersionString>.*?\n        </item>",
    "",
    content,
    flags=re.DOTALL,
)

content = content.replace(marker, marker + "\n" + new_item)

with open(appcast_path, "w") as f:
    f.write(content)
PYEOF

echo "Updated appcast.xml with version ${VERSION} (build ${BUILD_NUMBER})"
