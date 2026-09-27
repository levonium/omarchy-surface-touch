# omarchy-surface-touch

Touchscreen and pen for a **Surface Pro 7+** on the **stock Omarchy kernel**
(`linux-omarchy`), without switching to the linux-surface kernel. Plus an
on-screen keyboard with a toggle button in the Omarchy bar.

Everything installs as local pacman packages, so `pacman` tracks every file and
one command removes it all.

| Directory | Package | What it is |
|---|---|---|
| `ithc-dkms/` | `ithc-dkms` | Touch controller driver, rebuilt by DKMS on every kernel update |
| `iptsd/` | `iptsd` | Daemon that turns raw touch data into multitouch and pen input |
| `wvkbd/` | `wvkbd-deskintl` | On-screen keyboard (desktop layout) |
| `omarchy-plugin/levonium.osk/` | none (copied into your config) | Bar button that shows/hides the keyboard |
| `scripts/check.sh` | none | Read-only health check |
| `scripts/update-ithc.sh` | none | Pulls a newer driver from linux-surface |

Tested 2026-09-27 on a Surface Pro 7+ (SKU 1960), kernel `7.2.5-3-omarchy`:
touch, multitouch and suspend/resume all work.

---

## Install

Run everything from a normal terminal (`sudo` needs one to ask for your
password.

### 0. Prerequisites

```bash
sudo pacman -S --needed base-devel git linux-omarchy-headers
git clone <this repo> ~/Code/omarchy-surface-touch   # skip if already here
cd ~/Code/omarchy-surface-touch
```

The headers must match the kernel you run (`uname -r`). Omarchy updates the
kernel and headers together.

### 1. Touch driver (ithc-dkms)

```bash
cd ithc-dkms
makepkg -sirc
cd ..
```

This installs `dkms` from the official repos, then builds the driver for your
installed kernels. It's normal to see a warning about missing headers for
any kernel you don't have headers for (e.g. the stock `linux` package); only
`linux-omarchy` matters.

Load it now (or just reboot):

```bash
sudo rmmod ithc 2>/dev/null   # unload a manually loaded test copy, if any
sudo modprobe ithc
```

After this, single-finger touch already works (the controller's built-in basic
mode).

### 2. Touch daemon (iptsd)

```bash
cd iptsd
makepkg -sirc
cd ..
```

The build downloads its libraries (fmt, spdlog, eigen, …) and links them in
statically, so it needs internet access.

Start it for the current session (on later boots and after every
suspend/resume, udev starts it automatically):

```bash
sudo udevadm trigger --subsystem-match=hidraw --action=add
```

Now multitouch (two-finger scroll, pinch) and palm rejection work.

### 3. On-screen keyboard (wvkbd-deskintl)

```bash
cd wvkbd
makepkg -sirc
cd ..
rm -f ~/.local/bin/wvkbd-deskintl   # remove the pre-package manual copy, if any
```

### 4. Keyboard button in the bar

```bash
cp -r omarchy-plugin/levonium.osk ~/.config/omarchy/plugins/
omarchy bar put levonium.osk --before omarchy.bluetooth
omarchy restart shell
```

Tap the keyboard icon to show/hide the keyboard. The first tap starts it.

The restart matters when the plugin was removed and added back in the same
session: the bar then shows the icon but keeps a stale copy that ignores
clicks, and `omarchy-shell shell rescanPlugins` doesn't clear it.

### 5. Verify

```bash
./scripts/check.sh
```

Every line should say `ok`. Then reboot once and run it again.

---

## Undo everything

```bash
sudo pacman -Rns ithc-dkms iptsd wvkbd-deskintl   # also removes dkms if nothing else needs it
rm -rf ~/.config/omarchy/plugins/levonium.osk
```

Then remove the `{ "id": "levonium.osk" }` entry from the `right` list in
`~/.config/omarchy/shell.json` (the bar reloads on save). Reboot, or
`sudo rmmod ithc`, to unload the driver right away.

Nothing else is changed: no kernel swap, no boot options, no files outside
the packages and the plugin folder.

---

## After a kernel update

Normally nothing is needed: DKMS rebuilds `ithc` during `omarchy update` /
`pacman -Syu`.

**If touch stops working after an update:**

```bash
./scripts/check.sh
dkms status ithc
```

If DKMS says the build failed, the new kernel changed something the driver
uses. The system still boots; only touch is affected. To fix:

1. See the error: `cat /var/lib/dkms/ithc/*/build/make.log | tail -30`
2. Get a newer driver from linux-surface for your kernel series (e.g. `7.3`):
   ```bash
   ./scripts/update-ithc.sh 7.3
   # or, if their support is still an open PR:
   ./scripts/update-ithc.sh 7.3 <fork-owner>/linux-surface <branch>
   ```
   Find the PR at <https://github.com/linux-surface/linux-surface/pulls>
   ("Add patches for 7.x").
3. Review `git diff`, note the new source in "Where the driver comes from" below, then:
   ```bash
   cd ithc-dkms && makepkg -sirc && cd ..
   sudo modprobe ithc
   ```
4. Commit the update.

---

## Known limitations

- **Slight lag, occasional missed taps.** The driver polls the controller
  instead of using interrupts (`poll=1`, set in `/usr/lib/modprobe.d/ithc.conf`).
  A tap can occasionally fall between two polls when the screen has been idle.
  Interrupts need either the linux-surface kernel patch or the boot option
  `intremap=nosid` (disables interrupt source-ID checks for *all* devices; not
  used here on purpose, untested).
- **Kernel is marked "tainted"** (unsigned out-of-tree module). Only matters
  when filing kernel bug reports.
- **Battery during long sleep** has not been measured yet.

---

## How it works (and why not IPTS)

The Surface Pro 7+ touchscreen doesn't work like a normal one. Its chip sends a
raw capacitive **heatmap**, and the host has to compute finger positions.

- Older Surfaces (Pro 4 to 7) deliver that data through the Intel Management
  Engine, using the **IPTS** driver.
- The **Pro 7+** (Tiger Lake) uses the **Intel Touch Host Controller** instead:
  PCI `00:10.6`, ID `8086:a0d0`. That needs the **ithc** driver. The IPTS
  driver builds fine but has nothing to bind to on this machine.

Neither driver is in the mainline kernel; both live in the linux-surface patch
set. linux-surface ships them inside its own kernel, which in September 2026 was
still on 6.19 while Omarchy was on 7.2. This repo builds only the ithc driver as
an out-of-tree DKMS module against the kernel you already run.

The linux-surface patch also changes the kernel's interrupt remapping for this
device (the controller sends interrupts with the wrong source ID). The driver's
`poll=1` option avoids interrupts entirely, so no kernel patch is needed.

Once loaded, ithc exposes:

- a basic single-touch device (the controller's fallback mode),
- a pen device,
- raw data channels on `/dev/hidrawN`.

`iptsd` reads the raw channels and creates `IPTSD Virtual Touchscreen` and
`IPTSD Virtual Stylus` input devices with real multitouch. On resume the driver
re-initialises the controller, which creates a new `hidrawN`. The packaged udev
rule starts `iptsd@dev-hidrawN.service` for it, and the old instance stops.

---

## Where the driver comes from

`ithc-dkms/ithc/` holds the unmodified `drivers/hid/ithc/` files from
linux-surface's `patches/7.2/0006-ithc.patch`:

- Repo/branch: `Apiznel/linux-surface`, branch `7.2`, commit `6bcf30a`
  (linux-surface PR #2233, "Add patches for 7.2", not yet merged)
- Snapshot: 2026-09-13 (`pkgver 7.2.20260913`)
- License: GPL-2.0 OR BSD-2-Clause (see file headers)

The source is copied into this repo on purpose: the PR may be rebased, merged
or deleted, and this repo should always rebuild exactly what was tested.

Other sources are pinned by checksum in their PKGBUILDs:

- iptsd v3.1.0: <https://github.com/linux-surface/iptsd>
- wvkbd v0.20: <https://git.sr.ht/~proycon/wvkbd>
