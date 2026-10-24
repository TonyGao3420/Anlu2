# SC520 Lab3 architecture

## 1. Official main chain

- camera configuration
- MIPI D-PHY RX
- CSI unpack
- RAW10 unpack
- ISP processing
- DDR storage and readback
- HDMI output generation

This is the base path and is considered the stable foundation.

## 2. Display and overlay layer

- `hdmi_mixer.v`
- `hdmi_tx.v`
- OSD / logo / overlay related logic

This layer is used for visual presentation and debugging overlays.

## 3. Track2 extension layer

- `track2_lab3_merge.v`

Responsibilities:
- target detection
- ROI filtering
- bbox generation
- centroid and area calculation
- self-check status
- bbox redraw on video output

## 4. Project rule

Do not rewrite the main video pipeline. The Track2 module should be inserted only as a functional extension on top of the official pipeline.

## 5. Current engineering direction

The final project should remain under:

- `D:\HX1P35A_Contest_202606\lab_ex3_osd_SC520`

This directory is the real project root for final integration and validation.
