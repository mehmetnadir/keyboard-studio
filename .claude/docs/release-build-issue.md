# App exits silently at launch — cause and fix

**Cause: stale TCC / container state, not the build.** Fixed by resetting both.

```sh
tccutil reset All dev.keyboardstudio.app
rm -rf ~/Library/Containers/dev.keyboardstudio.app
lsregister -f "/Applications/Keyboard Studio.app"
```

`scripts/install.sh` now does this automatically.

## What it looked like

Launched through LaunchServices (`open`, or Finder) the app exited immediately:
no crash report, no sandbox denial, nothing in the system log. Invoking the
binary directly from a terminal still worked, which sent the investigation in
the wrong direction for a while.

## How the diagnosis went wrong, and how it was caught

Each hypothesis was tested by swapping one thing at a time:

| Test | Result | Read as |
|---|---|---|
| Release binary in a working debug bundle | exits | the binary, not the bundle |
| Debug build | ran | release-specific |
| Release with `-Onone` | ran | **optimisation is the trigger** |
| Release with `-Onone` via the build script | exits | contradiction |
| Debug build again | now exits too | the earlier reading was wrong |
| Last commit, without local changes | still exits | not the code at all |

The `-Onone` result was a false positive: deleting the sandbox container
mid-investigation changed the state between runs, so two tests that looked like
a controlled comparison were not. The tell was the contradiction — the same
configuration passing and then failing. **A hypothesis that requires two
identical runs to disagree is wrong.**

Once "does the committed code fail too?" was asked, it took one test to move
from the binary to the environment.

## Real fix

Deleting the container by hand leaves TCC holding approvals for an identity
whose container no longer exists, and the app cannot start. Resetting both puts
them back in agreement. The permission prompt appears again afterwards, which
is expected.

## Genuine bug found along the way

`MainActor.assumeIsolated` was used in timer and notification callbacks. Those
run on the main *thread*, which is not the same as being main-actor isolated —
checked in debug, undefined in release. Replaced with `Task { @MainActor }`,
except at `willTerminate`, which must stay synchronous or pending key counts
would not be flushed before exit.
