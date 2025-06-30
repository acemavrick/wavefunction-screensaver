# Wavefunction Screensaver

A macOS screensaver that simulates wave propagation using Metal.

## Features

- Real-time wave simulation using the wave equation
- Metal-accelerated computation and rendering
- Random disturbances create an ever-changing pattern
- Efficient implementation with minimal CPU usage

## Requirements

- A Mac with Metal support
- Xcode (for now)

## Important Notes

- ⚠️ This screensaver uses Metal for GPU acceleration and **will consume significant GPU resources**. Not recommended for use on battery-powered devices for extended periods.
- ⚠️ There is a known issue where the screen saver continues to use resources even after it is dismissed under the process `legacyScreenSaver`. After some time, this can **severely slow down the computer** and therefore **the process must be manually killed every time the screensaver is dismissed**. A fix is being looked into, but until then, use the screensaver at your own risk.
- If you experience any graphical glitches or performance issues, please file an issue.

## Installation

For now, the only way of installing is to build from source.

1. Clone this repository.
2. Open the project with Xcode.
3. Build the project.
4. Navigate to the built `Wavefunction Screensaver.saver` and open it in System Settings.
5. Select the screensaver to use it.

## How It Works

This screensaver implements a numerical solution to the 2D wave equation using Metal compute shaders. The simulation uses three buffers to store the previous, current, and next states of the wave. Random disturbances are periodically added.

This project is built with Swift and Metal. The main components are:

- `WaveView.swift`: Main view controller that handles Metal setup and animation
- `Shaders.metal`: Contains compute and fragment shaders for wave simulation and rendering

## Planned Features

*(not in any specific order)*

- Usage of Metal Performance Shaders for optimization?
- Fix the resource usage issue when screensaver is dismissed
- Add a notarized release.

## Contribution

Feel free to contribute through issues and/or pull requests. Email also works.

## Acknowledgements

- Apple Documentation
- [JellyFish Screensaver](https://github.com/Eskils/JellyfishSaver.git)
