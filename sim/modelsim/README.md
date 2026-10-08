Current ROI regressions use green-only connected regions and stable frame-atomic boxes. See ../../doc/GREEN_ROI_20261008.md for coverage and limitations.

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

The 720p ROI height regression checks four locked frames of a 600-pixel-tall target.
