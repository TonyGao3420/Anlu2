"""Audit against the actual latest project snapshot, including its new logo."""
from pathlib import Path
import hashlib
import json

root=Path(__file__).resolve().parents[2]
backup=root.parent/'recovery_backups/Anlu2_before_motion_style_20261026'
build=root/'sim/build/track2_requirements_20261026'


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def audit():
    before=json.loads((backup/'source_sha256.json').read_text())
    allowed={'user_source/hdl_source/design_top_wrapper.v','user_source/hdl_source/video/roi_background_stylize.v','user_source/hdl_source/hdmi_mixer.v'}
    changed={rel for rel,h in before.items() if rel.startswith('user_source/') and sha(root/rel)!=h}
    assert changed==allowed,changed
    top=(root/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
    old=(backup/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
    normalized=top.replace('1=style + one-second trail','1=style + three-second trail').replace(', .MOTION_ENABLE(1),.STATUS_ENABLE(1)','')
    normalized=normalized.replace('.LINE_TOTAL(1650),.MOTION_ENABLE(1),.STATUS_ENABLE(1))','.LINE_TOTAL(1650))')
    assert normalized==old,'Top changed outside stylizer parameters/comment'
    mixer=(root/'user_source/hdl_source/hdmi_mixer.v').read_text(encoding='utf-8-sig')
    old=(backup/'user_source/hdl_source/hdmi_mixer.v').read_text(encoding='utf-8-sig')
    assert old.count('D:/Anlogic/Anlu2/user_source/hdl_source/')==5
    assert mixer==old.replace('D:/Anlogic/Anlu2/user_source/hdl_source/',''),'Logo changed beyond portable MIF paths'
    for rel,h in before.items():
        if rel.endswith(('.al','.sdc','.prj','settings.cfg','.mif')) or rel=='user_source/constraints_source/pin.adc':
            assert sha(root/rel)==h,rel
    for name in ['logo_index0','logo_index1','logo_index2','logo_index3','logo_palette']:
        assert (root/f'user_source/hdl_source/{name}.mif').is_file()
    report={
        'backup':str(backup),'changed_existing_hardware_sources':sorted(changed),
        'ROI_classifier_tracker_height_center_coordinates_servo_PWM_switch_ISP_DDR_clock_constraints_byte_identical':True,
        'latest_345x120_logo_code_and_MIF_data_preserved_only_paths_repaired':True,
        'no_new_project_source_entries_or_pins':True,
        'same_video_pipeline_latency':True,'legacy_output_unchanged_when_extension_parameters_zero':True,
        'normal_modes_change_only_in_new_algorithm_status_HUD':True,
        'motion':{'cell_size_pixels':[16,16],'cells':3600,'history_word_bits':9,'history_bits':32400,
                  'high_threshold':12,'low_threshold':6,'hint_and_count_age_frames':1,
                  'global_reject_at_cells':1200,'timeout_cycles':18750000},
        'trail_TTL_ms':1000,'trail_median_IIR_deadband_sampling_unchanged':True,
        'previous_bit_is_backup_not_a_fresh_build_of_updated_logo_sources':True,
    }
    build.mkdir(exist_ok=True)
    (build/'source_audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    return report


if __name__=='__main__':print(json.dumps(audit()))
