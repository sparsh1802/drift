# Drift

A menu-bar weather overlay for macOS. Snow falls over your desktop, settles on window tops and the Dock, slides off when you drag a window, and scatters when you sweep the pointer through it.

Universal app (Apple Silicon + Intel), macOS 12 Monterey or newer. No permissions are needed; it reads window positions only, never their contents.

Snow only shows where there are no app windows: on the desktop, on top of windows and on the Dock. Nothing is drawn over a full-screen app.

## Snowballs and snowmen
Drift takes the mouse only while the pointer is over snow, a snowball, a snowman, a tree, a gift or Santa. Clicks everywhere else go to your apps and the desktop as usual, and clicking snow doesn't draw the desktop's selection box.

- **Roll:** press on a snow pile and drag along it. A snowball forms and grows as it picks up snow.
- **Stack:** let go of a ball on top of another ball. Three stacked balls, in any order, become a snowman with a face, a carrot nose, stick arms and a scarf, and sometimes a top hat.
- **Pick up:** drag any ball, or the top of a snowman, to lift it off and move it.
- **Throw:** let go while moving fast. A hard hit on a snowman's head knocks it off.
- **Click a snowman** to make it wobble.
- **Build a Snowman** in the menu makes one instantly.

## Christmas trees, Santa and gifts
- **Plant a Christmas Tree** in the menu adds a tree with baubles, a glowing star, string lights and presents. You can have up to 6.
- **Click a tree** to shake it and switch the lights: colour twinkle, warm white, chase, or off. Drag it to move it onto another window or the Dock. Trees ride along when you move the window they sit on.
- **Santa** flies along the Dock every 30 to 60 minutes (turn off **Santa Visits** to stop this), or whenever you choose **Send Santa**. He drops a gift. Click Santa for up to two more gifts, and click a gift to open it.

## Weather modes
- **Snow**: piles up on windows, the Dock and the screen bottom. Drag or fling a window to throw its snow off.
- **Rain**: streaks with splashes on window edges and occasional lightning.
- **Autumn Leaves / Sakura**: tumble down, rest on windows, and scatter when the pointer brushes them.
- **Fireflies**: drift around and gather where the pointer rests.
- **Starfall**: meteors streak across and burst into sparks on windows.

Menu-bar options: intensity, wind, settle on windows/Dock, cursor interaction, behind-windows mode, battery saver (half the particles at 30 fps on battery or in Low Power Mode), shake everything off, pause, open at login.

## Build
```bash
./build.sh
```
This produces `build/Drift.app` and `dist/Drift.zip`. It needs only the Xcode Command Line Tools (`xcode-select --install`).

## Moving it to another Mac (for example an M2 MacBook)
1. Copy `dist/Drift.zip` over (AirDrop, USB or cloud), unzip it and drag `Drift.app` into `/Applications`.
2. The app is self-signed, so macOS blocks it the first time. Either:
   - open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**, or
   - run `xattr -dr com.apple.quarantine /Applications/Drift.app` in Terminal.
3. Look for the snowflake in the menu bar.

You can also clone this repo on that Mac and run `./build.sh`.
