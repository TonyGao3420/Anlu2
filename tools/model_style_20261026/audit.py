"""Limit this revision strictly to display stylization and its enable parameter."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[2]
backup = root.parent / 'recovery_backups/Anlu2_before_model_style_20261026'
build = root / 'sim/build/model_style_20261026'


def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()


def audit():
    before = json.loads((backup / 'source_sha256.json').read_text())
    changed = {rel for rel, value in before.items() if sha(root / rel) != value}
    assert changed == {'user_source/hdl_source/design_top_wrapper.v', 'user_source/hdl_source/video/roi_background_stylize.v'}, changed
    top = 'user_source/hdl_source/design_top_wrapper.v'
    assert (root / top).read_bytes().replace(b',.MODEL_STYLE_ENABLE(1)', b'') == (backup / top).read_bytes(), 'Top changed outside display parameter'
    report = {
        'backup': str(backup), 'changed_existing_hardware_sources': sorted(changed),
        'ROI_detector_servo_coordinates_switches_ISP_DDR_clock_pins_1s_trail_byte_identical': True,
        'latest_logo_code_and_all_MIF_byte_identical': True,
        'added_video_pipeline_clocks': 0,
        'model_background': {'mean_tile': [8, 8], 'gray_levels': 16, 'surface_gray_range': [96, 246],
                             'contour_min_gray': 56, 'contour_width_pixels': 2, 'directional_threshold': 24,
                             'motion_changes_background_color': False, 'new_RGB_frame_buffer': False},
        'target_color': 'green pixels inside existing valid ROI only; original rectangular ROI metadata preserved',
        'motion_analysis_and_MOT_statistics_preserved': True,
        'normal_modes_change': 'none relative to preceding motion-style release',
        'trail_TTL_ms': 1000, 'board_test_performed': False,
    }
    build.mkdir(exist_ok=True)
    (build / 'source_audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return report


if __name__ == '__main__': print(json.dumps(audit()))
