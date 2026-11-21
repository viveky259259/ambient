#!/bin/zsh
# APP-026 · `scripts/cut-release.sh` refuses an unsafe release and its dry run changes nothing.
# timeout: 120
# Runs in a local clone of this repository in the case's folder. Its remote points nowhere, and `swift` and `gh` are
# stand-ins that fail, so a run that went past the dry run could neither test, commit to this repository nor push.
source "$QA_REPO/qa/run/lib.sh"

repo=$QA_ROOT/repo
# A CI checkout has no local main branch, only origin/main; take whichever exists.
main_ref=$(git -C "$QA_REPO" rev-parse -q --verify refs/heads/main >/dev/null && echo refs/heads/main || echo refs/remotes/origin/main)
git clone -q --no-hardlinks --no-checkout "$QA_REPO" "$repo" 2>/dev/null \
  && git -C "$repo" fetch -q --update-head-ok "$QA_REPO" "+${main_ref}:refs/heads/main" 2>/dev/null \
  && git -C "$repo" checkout -q main 2>/dev/null || { echo "cannot clone main" >&2; exit 2; }
git -C "$repo" remote set-url origin "$QA_ROOT/no-such-remote"
git -C "$repo" config user.email qa@example.invalid
git -C "$repo" config user.name QA
mkdir -p "$QA_ROOT/fakebin"
for tool in swift gh; do print -r -- '#!/bin/sh
echo "stand-in $0 must not run" >&2; exit 99' > "$QA_ROOT/fakebin/$tool"; chmod +x "$QA_ROOT/fakebin/$tool"; done
cut() { (cd "$repo" && PATH="$QA_ROOT/fakebin:$PATH" scripts/cut-release.sh "$@" 2>&1); }
current=$(sed -n 's/.*current = "\(.*\)".*/\1/p' "$repo/Sources/AmbientBase/Version.swift")
head=$(git -C "$repo" rev-parse HEAD)

# Step 1: a feature branch.
git -C "$repo" checkout -q -b qa/feature
out=$(cut 9.9.9); code=$?
assert_eq "$code" 1 "exit code on a feature branch"
assert_eq "$out" "cut-release: cut releases from main." "on a feature branch"
git -C "$repo" checkout -q main

# Step 2: main, no changelog section.
out=$(cut 9.9.9); code=$?
assert_eq "$code" 1 "exit code without a changelog section"
assert_eq "$out" "cut-release: add a '## 9.9.9 — $(date +%F)' section to CHANGELOG.md first." "without a changelog section"

# Step 3: not a version, and the current version.
out=$(cut 9.9); code=$?
assert_eq "$code" 1 "exit code for 9.9"
assert_eq "$out" "cut-release: usage: scripts/cut-release.sh <major.minor.patch> [--dry-run]" "for 9.9"
out=$(cut $current); code=$?
assert_eq "$code" 1 "exit code for the current version"
assert_eq "$out" "cut-release: $current is already the current version." "for the current version"

# Step 4: a dry run with the changelog section added.
{ print "# Changelog\n\n## 9.9.9 — $(date +%F)\n"; tail -n +2 "$repo/CHANGELOG.md"; } > "$QA_ROOT/CHANGELOG.md"
cp "$QA_ROOT/CHANGELOG.md" "$repo/CHANGELOG.md"
out=$(cut 9.9.9 --dry-run); code=$?
assert_eq "$code" 0 "exit code of the dry run"
for f in Sources/AmbientBase/Version.swift site/index.html site/thanks.html site/llms.txt; do
  assert_contains "$out" "$f" "the dry run's diff stat"
done
assert_eq "${out##*$'\n'}" "Dry run: nothing committed; files restored." "the dry run's last line"
assert_eq "$(git -C "$repo" status --porcelain)" " M CHANGELOG.md" "git status after the dry run"
assert_eq "$(git -C "$repo" rev-parse HEAD)" "$head" "HEAD after the dry run"
assert_eq "$(git -C "$repo" tag -l v9.9.9)" "" "tags after the dry run"
