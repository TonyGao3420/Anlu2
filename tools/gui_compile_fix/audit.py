"""Check pure module relocation and GUI-normalized project metadata."""
from pathlib import Path
import hashlib
import json
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[2]
build = root / 'sim/build/gui_compile_fix_20261025'
backup = root.parent / 'recovery_backups/Anlu2_before_GUI_project_fix_20261025'
marker = '\n// Integrated ERAM logo definition: keep the mixer self-contained for TD source lists.\n'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def project_tree(path):
    return ET.fromstring(path.read_text(encoding='utf-8-sig').replace('&', '&amp;').replace('::', '__'))


def project_semantics(node):
    # TD recomputes these bookkeeping fields when opening/saving a project.
    if node.tag == 'MiscSettings':
        assert all(c.tag == 'Setting' and c.attrib == {'Key': 'farm', 'Val': 'disable'} for c in node)
        return None
    if node.tag == 'Attr' and node.get('Name') in ['CompileOrder', 'AutoExcluded']:
        return None
    return (node.tag, sorted(node.attrib.items()), (node.text or '').strip(),
            [v for c in node if (v := project_semantics(c)) is not None])


def audit():
    prior = json.loads((backup / 'before_release_manifest.json').read_text(encoding='utf-8'))
    allowed = {'user_source/hdl_source/hdmi_mixer.v', 'user_source/hdl_source/anlogic_logo_eram.v'}
    changed = {p for p, h in prior['source_sha256'].items()
               if p.startswith('user_source/') and sha(root / p) != h}
    assert changed == allowed, changed
    old_mixer = (backup / 'hdmi_mixer.v').read_text(encoding='utf-8-sig')
    old_logo = (backup / 'anlogic_logo_eram.v').read_text(encoding='utf-8-sig')
    mixer = (root / 'user_source/hdl_source/hdmi_mixer.v').read_text(encoding='utf-8-sig')
    prefix, logo = mixer.split(marker)
    assert prefix.rstrip('\n') == old_mixer.rstrip('\n'), 'Mixer logic changed'
    assert logo == old_logo, 'Logo definition/data changed'
    placeholder = (root / 'user_source/hdl_source/anlogic_logo_eram.v').read_text()
    assert not re.search(r'^\s*module\s', placeholder, re.M), 'Duplicate logo definition'
    project = root / 'td_project/camera_to_dsi_display.al'
    assert project_semantics(project_tree(project)) == project_semantics(project_tree(backup / 'camera_to_dsi_display.al'))
    sources = {(project.parent / f.get('Path')).resolve() for f in project_tree(project).findall('Source_Files/*/File')}
    assert all(p.is_relative_to(root) and p.is_file() for p in sources)
    for stage in ['syn_1', 'phy_1']:
        worker = root / 'td_project/camera_to_dsi_display_Runs' / stage
        prj = worker / 'camera_to_dsi_display.prj'
        if prj.exists():
            actual = {(prj.parent / f.get('Path')).resolve() for f in project_tree(prj).findall('Source_Files/*/File')}
            assert actual == sources, stage
        if (worker / 'settings.cfg').exists():
            assert (worker / 'settings.cfg').read_bytes() == (backup / 'camera_to_dsi_display_Runs' / stage / 'settings.cfg').read_bytes(), stage
    for p, h in prior['source_sha256'].items():
        if p.endswith('.sdc') or p == 'user_source/constraints_source/pin.adc':
            assert sha(root / p) == h, p
    report = {
        'changed_production_files': sorted(changed),
        'mixer_logic_exactly_preserved': True, 'logo_definition_and_data_exactly_preserved': True,
        'all_other_production_files_byte_identical_to_1s_release': True,
        'project_source_set_hardware_top_and_strategy_unchanged': True,
        'GUI_metadata_changes_only': ['compile-order renumbering', 'unused-module auto-exclusion', 'local-host setting'],
        'pins_and_timing_constraints_unchanged': True,
        'gui_generated_worker_sources_match_main_project': True,
        'previous_release_sha256': prior['sha256'], 'backup': str(backup),
    }
    build.mkdir(exist_ok=True)
    (build / 'source_audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return report


if __name__ == '__main__':
    print(json.dumps(audit()))
