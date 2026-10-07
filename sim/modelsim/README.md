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
unit-gain AWB stream. The AWB and display-buffer RAM models in the testbenches
are behavioral; this is RTL simulation of the selected logic, not a timing or
vendor primitive simulation of the complete board-level MIPI/DDR design.
