# HDL source organization

This directory is organized by design layer to keep the official SC520 Lab3 project clear and maintainable.

## Directory structure

- `camera/` : sensor and camera frontend wrappers
- `video/` : HDMI, timing, output path wrappers
- `track2/` : target detection, bbox, centroid, ROI and overlay logic
- `debug/` : debug and status utilities
- `isp/` : ISP and image-processing logic
- `mipi_dphy_rx/` : MIPI receive layer
- `ph1p35_ddr/` : DDR wrapper
- `uics520_cfg/` : SC520 sensor register configuration
- `uiisp_beta/` : AE and helper logic

## Important rule

The official video chain is the base design. The Track2 extension layer must sit on top of this base path and should not replace the main signal flow.
