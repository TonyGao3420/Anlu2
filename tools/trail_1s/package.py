"""Compatibility entry point for the current main-project release."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).resolve().parents[1]/'track2_20261026/package.py'),run_name='__main__')
