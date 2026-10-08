# ModelSim regression

Run from PowerShell in `Anlu2/sim`:

```powershell
.\run_model_regression.ps1
```

If `vsim.exe` is installed elsewhere, pass its path with `-ModelSimPath`.
The regression compiles the focused SystemVerilog testbenches and writes its
transcript to `Anlu2/sim/modelsim/run_regression.log`.

The checks cover red-target ROI acquisition/release and centroid, HDMI pixel
ordering/sync plus the rectangular overlay, the production display RGB lift,
RAW10/RAW8 byte order, BGGR interpolation on a flat color field, and the
unit-gain AWB stream. An additional AWB test feeds a synthetic green-cast
neutral field over several frames and checks that the enabled gain correction
raises red/blue while preserving green and stream length. The ROI regression
also checks a sparse H-shaped red object whose red pixels occupy less than half
of its bounding rectangle. The AWB and display-buffer RAM models in the
testbenches are behavioral; this is RTL simulation of the selected logic, not
a timing or vendor primitive simulation of the complete board-level MIPI/DDR
design.

Spatial color shading: `run_color_shading.do` checks transactional BGGR calibration, unity, a green-center/red-edge field, frozen gains on a red target, invalid-capture rollback and clear at SOF. `run_color_shading_720p.do` repeats this at 1280x720 (6,451,200 pixels). `run_lsc_keys.do` checks short/long-press release behavior. The main regression includes LSC, keys and 720p ROI checks; the full-size LSC test can be run separately.
