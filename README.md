<div align="center">

# Pause ⏸

**Reclaim RAM from apps you're not using — without losing your work.**

A free, open-source macOS menu bar app. Freeze an app instantly, or send it to sleep to
release *all* of its memory including swap. Bring it back whenever you want.

[![Download](https://img.shields.io/badge/Download-Pause%201.0.0.dmg-blue?style=for-the-badge)](https://github.com/fazalrshah/pause/releases/latest)
![Platform](https://img.shields.io/badge/macOS-14%2B-lightgrey?style=for-the-badge)
![Arch](https://img.shields.io/badge/Universal-Apple%20Silicon%20%2B%20Intel-black?style=for-the-badge)
![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)

</div>

---

## Why this exists

Local models changed what RAM is worth. Running a quick model on your own machine needs
several free gigabytes *right now* — but that memory is rarely free. It's scattered across a
browser you're not looking at, an Electron app idling in the background, a sync daemon, a
forgotten dev server. Meanwhile Claude, Codex, and everything else you actually use are
fighting over what's left.

Force-quitting is destructive; you lose your tabs and your place. Pause takes the memory back
and gives it to you again when you're done.

> **Free Up Memory** → set a target → Pause freezes background apps and services
> heaviest-first until it hits it → run your model → **Restore** puts everything back.

---

## Features

### ⏸ Pause — freeze an app instantly

Sends `SIGSTOP` to the app **and every one of its helper processes**. The app stops using CPU
entirely and macOS reclaims its resident memory. Resume is instant and byte-perfect: the app
continues mid-thought, same scroll position, same undo history, same everything.

*Why the whole process tree matters:* Chrome's memory doesn't live in Chrome. It lives in ~25
`Google Chrome Helper` processes. Freezing only the parent frees almost nothing.

### 🌙 Deep Sleep — release everything, including swap

Quits the app the normal way — exactly like pressing ⌘Q — so macOS and the app save state.
This is the only mechanism on macOS that returns **100% of an app's memory, swap included**.
Waking relaunches it and restores your windows and tabs in a few seconds.

Before the first use, Pause shows you what it's about to do, tells you whether *that specific
app* will restore its windows, and offers to turn window restore on for it.

**Your work is safe.** Apps that autosave save and quit. Apps that don't show their normal
"Do you want to save?" sheet and stay open — Pause leaves them frozen instead and tells you.
Nothing is ever force-quit.

### 🧠 Local Model Mode — one click, N gigabytes

Set a target with the slider. Pause freezes background apps and services, biggest first, until
it reaches it — never touching your frontmost app or anything protected. It remembers the exact
set it froze, so **Restore** undoes precisely that and leaves anything you froze by hand alone.

### ⚙️ Background services — the memory nothing else shows you

Activity Monitor buries them; most memory tools ignore them entirely. Pause enumerates every
process owned by your user, groups the loose ones by their parent service, and lists them with
their real memory cost — idle dev servers, updater daemons, sync helpers.

Services can be **frozen but never quit**: a daemon has no state-restoration contract, and
quitting one can break sync or backups. Around 30 critical processes (`WindowServer`,
`ControlCenter`, `coreaudiod`…) are permanently protected — freezing those would wedge your Mac.

### 📊 Honest memory numbers

Every row shows two figures, and the gap between them is the whole point:

- **Resident** (large) — RAM the app holds *right now*. This is what drops when you pause.
- **Footprint** (small, dim) — Activity Monitor's "Memory" column. It counts pages already
  compressed or swapped to disk, so it barely moves even after the RAM is fully reclaimed.

Measured on a 16 GB M1 with Chrome frozen:

```
Google Chrome — footprint 4.31 GB · resident 275 MB
```

Freezing returned ~4 GB of actual RAM while footprint hardly budged. Tools that show only
footprint make pausing look like it does nothing.

### ⏱ Per-app auto-pause

Any app can be set to freeze itself automatically after N minutes in the background, and thaw
when you come back. Per-app, off by default.

### 📈 System dashboard

Ring gauge with real pressure thresholds, a usage graph plotted against your total RAM (so
normal fluctuation looks normal), and a full App / Wired / Compressed / Free / Swap breakdown
from `host_statistics64`.

---

## Install

**[Download Pause-1.0.0.dmg →](https://github.com/fazalrshah/pause/releases/latest)**

1. Open the DMG and drag **Pause.app** to Applications.
2. First launch only: right-click Pause → **Open** → confirm.

Step 2 exists because Pause is ad-hoc signed rather than notarized (it's free and unfunded).
Look for the ⏸ icon in your menu bar — there's no Dock icon and no window.

### Build from source

Needs only Xcode Command Line Tools — no Xcode.

```bash
git clone https://github.com/fazalrshah/pause.git
cd pause
./build.sh              # native build
./build.sh --universal  # Apple Silicon + Intel
./package-dmg.sh 1.0.0  # build the DMG
```

---

## Why "Memory Used" might not drop

If your Mac is heavily oversubscribed — say 43 GB of logical memory on 16 GB of RAM — macOS
refills every freed page immediately by paging an *active* app back in. The system gauge stays
pinned near max even while Pause reclaims gigabytes. That's macOS working correctly, and it's
why per-app resident memory is the number to watch. To shrink the total for real, use **Deep
Sleep** — it's the only thing that releases swap.

## How it works, and what isn't possible

Pause uses `SIGSTOP`/`SIGCONT` and Apple's `libproc` APIs (`proc_pid_rusage`, `proc_pidinfo`).
No root, no kernel extension, no entitlements, no TCC prompts — these work on same-user
processes by design. Apple's guidance is explicitly to prefer `libproc` over `task_for_pid()`,
which SIP restricts to development tools.

**Checkpoint/restore is not possible on macOS.** The ideal design would snapshot a process to
disk and restore it byte-identically later. [CRIU](https://github.com/checkpoint-restore/criu)
does this on Linux via `ptrace`, `/proc` and parasite code injection — none of which exist on
macOS, and `task_for_pid` is SIP-locked. A state-preserving quit is the closest achievable
equivalent, which is what Deep Sleep is.

## Safety

- Quitting Pause resumes every frozen app — nothing is ever stranded.
- Sleeping apps persist to disk, so they stay listed and wakeable even if Pause crashes.
- If an app quits later, after you answer its save dialog, Pause notices and keeps it wakeable.
- Pause never touches itself, Finder, or the ~30 protected system processes.
- Nothing is ever `SIGKILL`ed. Ever.

## Caveats

- A frozen app beachballs if clicked and shows "Not Responding" in Activity Monitor — expected.
- Don't freeze an app mid-call or mid-upload; network connections drop.
- Window-restore quality varies by app. Browsers use their own "Continue where you left off"
  setting rather than macOS's, and Pause checks it for you.

## Documentation

- **[Architecture — module by module](docs/ARCHITECTURE.md)** — what every file does and why.

## License

MIT — see [LICENSE](LICENSE).
