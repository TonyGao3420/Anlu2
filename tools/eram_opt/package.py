from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).resolve().parents[1]/'trail_1s/package.py'),run_name='__main__')
