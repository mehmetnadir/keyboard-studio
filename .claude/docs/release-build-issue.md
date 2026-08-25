# App exits silently at launch — cause and fix

**Cause: App Sandbox on an ad-hoc signed build.** The sandbox entitlement was
removed; see PRIVACY.md for what that changes.

A sandboxed app needs a container, and macOS will not create one for a build
signed with `codesign --sign -`. The process dies before `main()` runs — which
is why adding NSLog traces to `init` and `onAppear` produced *nothing*: it never
got that far. That absence was the decisive clue.

The earlier fix below (resetting TCC and the container) made it launch once,
because a container that already existed could still be reused. Deleting the
container removed that crutch and exposed the real problem.

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


## Postscript: the real cause

Two wrong diagnoses preceded the right one, and both were wrong the same way —
a state change between runs made an uncontrolled comparison look controlled:

1. **Optimisation.** Debug passed, release failed, `-Onone` passed. But the
   container had been deleted in between, so the runs were not comparable.
2. **TCC/container staleness.** Resetting them worked — once — because the app
   recreated a container while the old TCC record was gone. It failed again on
   the next clean install.

What settled it was adding traces and finding **none of them ran**. An app that
produces no output from the first line of `init` has not failed *in* its code;
it has failed before its code. From there the sandbox was the only candidate.

The lesson worth keeping: when a bug appears to depend on build configuration,
first prove the configurations differ under *identical* environment state. And
when a trace at the very first line does not print, stop debugging the program
and start debugging its launch.

---

## Follow-up: permission was being asked for after every update

Symptom: after each rebuild macOS asked for Input Monitoring again, and until
it was granted the statistics tab showed `IOReturn 0xe00002e2`
(`kIOReturnNotPermitted`) and counted nothing.

Two independent causes, both now fixed.

**1. `install.sh` was deleting the grant itself.** It ran
`tccutil reset All dev.keyboardstudio.app` on every install — added while
chasing the launch bug, when a permission prompt was the cheap outcome and a
lost hour was the expensive one. Once the launch bug was actually fixed (the
sandbox), that line stopped being insurance and became the bug: every update
revoked the user's own grant. Removed.

**2. Ad-hoc signing gives a new identity on every build.** TCC keys a grant to
a code identity. `codesign --sign -` produces a fresh one each time, so macOS
genuinely saw each build as a different application — the previous grant was
not merely forgotten, it belonged to something else. `bundle.sh` now picks up a
`Developer ID Application` certificate when the machine has one and falls back
to ad-hoc otherwise, printing which it used. With a real certificate the
identity is stable and the grant survives rebuilds.

Verify with `codesign -dv --verbose=2 "/Applications/Keyboard Studio.app"` —
`Authority=Developer ID Application: …` means permissions will stick;
`Signature=adhoc` means they will not.

**Still open:** the App Sandbox is off. It was disabled because an ad-hoc
signed app cannot get a container. A Developer ID build can, so the sandbox
could now be restored — but it needs `com.apple.security.device.usb` to keep
HID access, and that combination is untested here. Not changed while the app is
working; noted so it is not forgotten.
