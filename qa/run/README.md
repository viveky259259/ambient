# Running QA cases on this Mac

The cases in `qa/cases/` are written for a person. Those a machine can check are also scripted
here, one script per case, and run on the Mac that tests Ambient:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/build-app.sh   # build/Ambient.app
qa/run/make-qa-app.sh                                                           # build/AmbientQA.app
node scripts/qa-run.ts                       # every scripted case
node scripts/qa-run.ts --area SET            # one area
node scripts/qa-run.ts EVT-029 EVT-035       # some cases
node scripts/qa-run.ts --changed origin/main # the scripted cases this branch's changes pick
```

Results print as they run and are written to `build/qa-results/<time>/summary.md` and
`results.json`. A failed case keeps its folder (`/tmp/aq.*`) for a look; passing ones are removed.

| Result | Meaning |
|---|---|
| ✔ pass | The script's checks held |
| ✘ FAIL | A check failed (exit 1): Ambient does not do what the case expects |
| ◌ known gap | The case is marked *Known gap* and failed, as expected |
| ? gap fixed | A *Known gap* case passed: the gap may be fixed, so update the case |
| ! ERROR | The script itself broke (exit 2 or more, a timeout, the app did not start) |

## How a case runs without touching this Mac's own Ambient

- **Its own app.** `build/AmbientQA.app` is the same build under another bundle id
  (`com.viveky259259.Ambient.qa`) and executable name (`AmbientQA`), so its settings domain is its
  own and nothing aimed at `Ambient` reaches it. Its settings are cleared before every app case.
- **Its own home.** Every case gets a fresh `/tmp/aq.XXXXXX` with `home/` as `HOME` (agent configs:
  `.claude`, `.codex`, …) and `a/` as `AMBIENT_HOME` (socket, state, logs, CLI link). Ambient reads
  every path from those two variables.
- **One app at a time.** Cases that start the app take a lock (`/tmp/ambient-qa.lock`), so runs in
  parallel queue for the screen and the settings domain. Cases without the app run freely.
- **Recorded agents, not real ones.** Scripts send the hook input each agent sends (from the
  adapters and `Tests/*/Fixtures`) instead of running Claude Code, Codex and the rest.

## What a script may not do

These touch the Mac outside the case's folder, so a case that needs them stays manual:

- Run `ambient` or the app outside `scripts/qa-run.ts`, or against the real `~` or `~/.ambient`.
- `open`, `pkill`, `killall` or `launchctl` anything; stop only what the script started, by pid.
- Read or write the Keychain (service `com.viveky259259.Ambient` is shared with the real app):
  online voice keys, `ambient task skill-bootstrap`.
- Change the desktop wallpaper, the login items, privacy permissions (`tccutil`), the audio
  driver, or `defaults` of `com.viveky259259.Ambient`.
- Use the network beyond loopback, or `sudo`.

## Drafts

`qa/run/drafts/` holds scripts that are written but not yet proven: they never ran, or they failed
and nobody has yet decided whether Ambient or the script is wrong. The runner ignores them, so a
merge run never reports a failure that is only a broken script. To promote one, run it once by
copying it into `qa/run/cases/`, then keep it there if it passes, or if it fails and reading the
source confirms Ambient is at fault.

## Writing a script

`qa/run/cases/<ID>.sh`, a zsh script named after its case:

```zsh
#!/bin/zsh
# EVT-035 · Tool output never leaves the hook or reaches the disk.
# needs-app: yes        # start build/AmbientQA.app first (default no)
# timeout: 60           # seconds (default 60)
# checks: part          # only some expected results are checked (default all); say which below
# slow: yes             # takes minutes; the merge run leaves it out (--skip-slow)
# Left to a person: the island's colour.
source "$QA_REPO/qa/run/lib.sh"
...
```

- Check the case's **Expected** results, not something easier. A check that cannot be made by a
  machine (a colour, an animation, a sound) is listed in a `Left to a person:` line and the script
  is marked `# checks: part`.
- Exit 0 when every check holds, 1 when one fails (`fail`, `assert_*`), 2 or more when the script
  could not run.
- Never loosen a check to make a case pass. If Ambient does not do what the case says, the case
  fails; if the case is wrong, fix the case.
- `lib.sh` has the helpers: `ambient`, `hook`, `fake_agent`, `listen_socket`, `state_get`,
  `wait_for` and the `assert_*` family.
