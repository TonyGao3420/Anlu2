# TD project entry

This directory is the entry point for the Anlogic TD project.

## Main project

- `camera_to_dsi_display.al` : top project file
- `camera_to_dsi_display.sdc` : timing constraints

## Design intent

The project keeps the official SC520 pipeline as the base design and adds the Track2 extension without breaking the original signal flow.

## Typical workflow

1. Open `camera_to_dsi_display.al` in Anlogic TD
2. Run synthesis
3. Run physical design
4. Verify HDMI output and camera pipeline
5. Debug Track2 overlay only after the base chain is stable
