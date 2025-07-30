# Wavefunction Screensaver

A macOS screensaver that simulates wave propagation using Metal.

## Features

- Real-time wave simulation using the wave equation
- Metal-accelerated computation and rendering
- Random disturbances create an ever-changing pattern
- Efficient implementation with minimal CPU usage
- Beautiful, mesmerising, unique scenes arising from mathematical models of nature

## Requirements

- A Mac with Metal support

## Important Notes

- ⚠️ This screensaver uses Metal for GPU acceleration and can consume significant GPU resources. Not recommended for use on battery-powered devices for extended periods.
- ⚠️ There is a known issue where the screen saver continues to use resources even after it is dismissed under the process `legacyScreenSaver`.
After some time, this may severely slow down the computer and therefore the process must be manually killed every time the screensaver is dismissed. However, I have noticed that, let alone for enough time, the system kills it off for you.
Frankly, I am not sure if there is a fix to this: it seems to be an inherent problem with Apple's handling of third party screensavers.
- If you experience any graphical glitches or performance issues, please file an issue or let me know.
- The settings/options pane may or may not work: this issue is being looked into.

## Solid Color Screens

A system for communicating basic issues/setups is built into the screensaver through the use of solid colored screens.

Normal:

- **Pink Screen**: Shown in preview mode (the little window in Settings). Shouldn't be shown when actually in use.
- **Blue Screen**: Battery saver mode is active (when on battery power). The screensaver just doesn't render to save resources and minimize energy usage.

Issues:

- **Red Screen**: Metal is not supported on your device
- **Yellow Screen**: Metal setup failed. This *shouldn't* show up, but if it does, try:
    1. `killall WallpaperAgent` (in Terminal)
    2. Restarting your computer
    3. Reinstalling. Right click on the screensaver in System Settings, delete it, then download the release again.

    If nothing works, reach out to me.

## Installation

Download and install the [latest release](https://github.com/acemavrick/wavefunction-screensaver/releases).
**Please make sure to read all the information for the release.**

## How It Works

This screensaver implements a numerical solution to the 2D wave equation using Metal compute shaders. The simulation uses three buffers to store the previous, current, and next states of the wave. Random disturbances are periodically added.

This project is built with Swift and Metal.

## Contribution

Feel free to contribute through issues and/or pull requests. Email also works.

## Acknowledgements

- Apple Documentation
- [JellyFish Screensaver](https://github.com/Eskils/JellyfishSaver.git)
