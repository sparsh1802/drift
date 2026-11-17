# ❄ Drift

**Live weather for your Mac desktop.** Snow falls, piles up on top of your windows and the Dock, and slides off when you drag a window. You can roll snowballs, build snowmen, decorate Christmas trees and wave at Santa as he flies past.

Drift is free and open source. It lives in your menu bar, needs no permissions, and stays out of your way: snow never covers the app you're working in.

---

## Install

**Option 1: one command.** Open **Terminal** and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/sparsh1802/drift/main/install.sh | bash
```

This downloads Drift, puts it in Applications and starts it. Look for the ❄ in your menu bar.

**Option 2: download it yourself.**

1. Download **[Drift.zip](https://github.com/sparsh1802/drift/releases/latest/download/Drift.zip)**, unzip it and drag **Drift** into **Applications**.
2. Open it. If macOS says it "can't be opened" or is from an "unidentified developer", go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. You only need to do this once.

> Why the warning? Drift isn't notarized by Apple, because that requires a paid developer account. The full source is right here if you'd like to check it, or build it yourself (see below).

**Requirements:** macOS 12 Monterey or newer, on Apple silicon or Intel Macs.

---

## What it does

### Weather
Pick one from the ❄ menu:

| | |
|---|---|
| ❄ **Snow** | Settles on window tops, the Dock and the bottom of the screen. Drag a window to make its snow slide off; fling it to send snow flying. |
| 🌧 **Rain** | Splashes on window edges, with the odd flash of lightning. |
| 🍂 **Autumn Leaves** | Tumble down and rest on windows. Brush past them to scatter them. |
| 🌸 **Sakura** | Cherry petals drift down and settle. |
| ✨ **Fireflies** | They wander about and gather around your pointer when it rests. |
| 🌠 **Starfall** | Meteors streak across and burst into sparks when they hit a window. |

### Play in the snow

| Do this | What happens |
|---|---|
| **Press on snow and drag along it** | Roll a snowball. It grows as it picks up snow. |
| **Drop a snowball on another one** | Stack them. **Three make a snowman**, with a carrot nose, a scarf and maybe a top hat. |
| **Drag a snowball (or a snowman's head)** | Pick it up and move it somewhere else. |
| **Let go while moving fast** | Throw it. A good hit knocks a snowman's head clean off. |
| **Click a snowman** | It wobbles. |

### Christmas extras
- **Plant a Christmas Tree** adds a tree with baubles, a glowing star, twinkling lights and presents. Click it to switch the lights; drag it onto any window or the Dock.
- **Santa** flies along the Dock with his reindeer every so often, or whenever you choose **Send Santa**. He drops a gift. Click it to open it, or click Santa for another one.

### Menu settings
Intensity and wind sliders, whether snow settles on windows and the Dock, a **Behind Windows** mode that keeps everything on the wallpaper, **Shake Everything Off**, **Pause**, and **Open at Login**.

---

## Good to know

- **Stays out of your way.** Snow only shows on your desktop, on top of windows and on the Dock. It never covers what you're working on, and nothing appears over full-screen apps. Clicks go straight through to your apps, except when you click on snow or a snowman.
- **No permissions, no tracking.** Drift reads where your windows are so snow can land on them, but never what's inside them. It doesn't connect to the internet.
- **Light on battery.** Drift uses your Mac's graphics chip, and on battery or in Low Power Mode it runs a lighter effect. You can turn that off in the menu.

---

## Uninstall

Quit Drift from its ❄ menu, then drag **Drift** from Applications to the Trash. If you turned on **Open at Login**, turn it off first, or delete `~/Library/LaunchAgents/local.drift.app.plist`.

---

## Build from source

You need the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/sparsh1802/drift.git
cd drift
./build.sh
open build/Drift.app
```

`build.sh` produces a single app that runs on both Apple silicon and Intel Macs (`build/Drift.app`), and a zip of it for sharing (`dist/Drift.zip`).

It's written in Swift, with rendering in Metal:

| File | What's in it |
|---|---|
| `Sources/Simulation.swift` | Weather particles and snow piling |
| `Sources/Snowplay.swift` | Snowballs and snowmen |
| `Sources/Festive.swift` | Trees, Santa and gifts |
| `Sources/Renderer.swift` | Metal drawing and shaders |
| `Sources/WindowTracker.swift` | Finds where your windows are |
| `Sources/Overlay.swift` | The see-through layer that holds the weather |
| `Sources/main.swift` | The menu bar menu |

Contributions are welcome. Open an issue or a pull request.
