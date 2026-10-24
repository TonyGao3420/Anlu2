# ModelSim regression

Run from PowerShell in `Anlu2/sim`:

```powershell
.\run_model_regression.ps1
```

Use `-ModelSimPath` if `vsim.exe` is elsewhere. The combined transcript is
`Anlu2/sim/modelsim/run_regression.log`.

The current seven groups cover:

- Green-only region selection, close-object separation, frame-atomic bounds,
  edge jitter, size convergence, dropouts, hollow shapes and SOF alignment.
- HDMI pixel order/sync and the existing ROI overlay.
- Production display gain 17/16, highlight clipping, protected overlays and
  sync signals during blanking; tone/saturation/sharpening remain disabled.
- RAW10/RAW8 byte order.
- BGGR interpolation of flat color fields.
- The supplied official AWB: neutral pixel order, gray-world correction,
  original gain range, green-channel preservation and highlight saturation.
- 720p: four locked frames of a 600-pixel-tall target, plus dense/fragmented
  scenes finishing within the 49,500-clock vertical blank budget.

AWB and display RAMs use functional models. The AWB divider model follows the
configured unsigned 48/32, 50-cycle contract. Hardware uses the real vendor IP.
This suite is not a full MIPI/DDR board simulation or post-route simulation.
The previous custom-AWB testbenches are historical; `run_awb.do` and
`run_awb_auto_gain.do` now delegate to `run_official_awb.do`.

See `../../doc/OFFICIAL_DISPLAY_20261009.md` and `../../doc/GREEN_ROI_20261008.md`.
