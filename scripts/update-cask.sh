#!/bin/zsh
# Writes the Homebrew cask for a published release into a checkout of viveky259259/homebrew-tap.
#
#   scripts/update-cask.sh 0.6.0 ../homebrew-tap      then commit and push the tap
#
# The checksum is the GitHub release's own digest of Ambient-<version>.dmg, the same file yaml.cafe serves (the Deploy
# site workflow checks that), so nothing is downloaded and no download is counted. The cask downloads from yaml.cafe
# with ?ref=brew, so Homebrew installs show up under their own launch tag in scripts/downloads.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?version, e.g. 0.6.0}
TAP=${2:?path to a homebrew-tap checkout}
[[ -d $TAP/.git ]] || { echo "$TAP isn't a git checkout of the tap." >&2; exit 66; }
SHA=$(gh release view "v$VERSION" -R viveky259259/ambient --json assets \
  --jq ".assets[] | select(.name == \"Ambient-$VERSION.dmg\") | .digest" | sed 's/^sha256://')
[[ $SHA =~ ^[0-9a-f]{64}$ ]] || { echo "No published Ambient-$VERSION.dmg with a SHA-256 digest." >&2; exit 1; }

mkdir -p "$TAP/Casks"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" > "$TAP/Casks/ambient.rb" <<'CASK'
cask "ambient" do
  version "@VERSION@"
  sha256 "@SHA256@"

  # ?ref=brew labels these downloads in yaml.cafe's counts, which store no IP address or cookie.
  url "https://yaml.cafe/downloads/Ambient-#{version}.dmg?ref=brew"
  name "Ambient"
  desc "Notch island, notifications and Dock glow for coding agents"
  homepage "https://yaml.cafe/"

  livecheck do
    url "https://github.com/viveky259259/ambient"
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Ambient.app"
  binary "#{appdir}/Ambient.app/Contents/Helpers/ambient"

  uninstall quit: "com.viveky259259.Ambient"

  zap trash: [
    "~/.ambient",
    "~/Library/Caches/com.viveky259259.Ambient",
    "~/Library/HTTPStorages/com.viveky259259.Ambient",
    "~/Library/Preferences/com.viveky259259.Ambient.plist",
  ]

  caveats <<~EOS
    Open Ambient and click Connect All, or run `ambient install`, to connect your agents.
    Before `brew uninstall --zap ambient`, run `ambient uninstall` to take Ambient's hooks
    out of your agents' settings.
  EOS
end
CASK
echo "Wrote $TAP/Casks/ambient.rb ($VERSION, sha256 $SHA)"
