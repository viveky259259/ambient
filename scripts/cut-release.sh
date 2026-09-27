#!/bin/zsh
# Cuts a release: sets the version everywhere it's stated (app, site, llms.txt), commits, tags and pushes.
# The Release workflow then builds, signs, notarizes, publishes and deploys yaml.cafe.
#
#   scripts/cut-release.sh 0.2.2             add a "## 0.2.2 — <date>" section to CHANGELOG.md first
#   scripts/cut-release.sh 0.2.2 --dry-run   show what would change, then put everything back
set -euo pipefail
cd "$(dirname "$0")/.."
die() { echo "cut-release: $1" >&2; exit 1; }

NEW=${1:-}
DRY=0
[[ ${2:-} == --dry-run ]] && DRY=1
[[ $NEW =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "usage: scripts/cut-release.sh <major.minor.patch> [--dry-run]"
OLD=$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/AmbientCore/Version.swift)
[[ $NEW != "$OLD" ]] || die "$NEW is already the current version."
[[ $(git branch --show-current) == main ]] || die "cut releases from main."
[[ -z $(git status --porcelain | grep -v ' CHANGELOG.md$') ]] || die "commit or stash your changes first (CHANGELOG.md may stay uncommitted)."
grep -q "^## $NEW" CHANGELOG.md || die "add a '## $NEW — $(date +%F)' section to CHANGELOG.md first."
git rev-parse -q --verify "refs/tags/v$NEW" >/dev/null && die "tag v$NEW already exists."

FILES=(Sources/AmbientCore/Version.swift site/index.html site/thanks.html site/llms.txt)
sed -i '' "s/current = \"$OLD\"/current = \"$NEW\"/" Sources/AmbientCore/Version.swift
for f in site/index.html site/thanks.html site/llms.txt; do
  sed -i '' -e "s/Ambient-$OLD\.dmg/Ambient-$NEW.dmg/g" -e "s/Ambient $OLD/Ambient $NEW/g" \
    -e "s/\"softwareVersion\": \"$OLD\"/\"softwareVersion\": \"$NEW\"/" -e "s/Version $OLD/Version $NEW/" \
    -e "s/Current version: $OLD/Current version: $NEW/" "$f"
done
scripts/check-site.sh "$NEW"

if (( DRY )); then
  git --no-pager diff --stat -- "${FILES[@]}"
  git checkout -- "${FILES[@]}"
  echo "Dry run: nothing committed; files restored."
  exit 0
fi

swift test --quiet
git add "${FILES[@]}" CHANGELOG.md
git commit -q -m "release: $NEW"
git tag -a "v$NEW" -m "Ambient $NEW"
# viveky259259 repos push over HTTPS with gh's credentials (the SSH key belongs to another account).
git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push -q origin main "v$NEW"
echo "Pushed v$NEW. Follow the release: gh run watch -R viveky259259/ambient \$(gh run list -R viveky259259/ambient -w Release -L1 --json databaseId -q '.[0].databaseId')"
