"""Analyze values transcribed from the FPGA's numeric diagnostic panel.

No phone-image pixel colors are used. No file produced here changes FPGA colors.
Input: nine rows `node B Gb Gr R r g b Q`, all measurements hexadecimal.
Q is RAW-valid, RAW-clipped, RGB-valid, RGB-clipped, for example 1010.
"""
import argparse
import json
import statistics
from pathlib import Path


def load_panel(path):
    rows = {}
    for line_no, line in enumerate(Path(path).read_text(encoding='utf-8-sig').splitlines(), 1):
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 9:
            raise ValueError(f'{path}:{line_no}: expected node, 4 RAW, 3 RGB, Q')
        node = int(parts[0], 10)
        if not 0 <= node < 9 or node in rows:
            raise ValueError(f'{path}:{line_no}: invalid/duplicate node {node}')
        values = [int(v, 16) for v in parts[1:8]]
        if any(not 0 <= v <= 1023 for v in values[:4]):
            raise ValueError(f'{path}:{line_no}: RAW outside 0..3FF')
        if any(not 0 <= v <= 255 for v in values[4:]):
            raise ValueError(f'{path}:{line_no}: RGB outside 0..FF')
        q = parts[8]
        if len(q) != 4 or any(c not in '01' for c in q):
            raise ValueError(f'{path}:{line_no}: invalid Q={q}')
        if q[:2] != '10':
            raise ValueError(f'{path}:{line_no}: Q={q}: RAW incomplete/clipped; recapture')
        rows[node] = {'raw': values[:4], 'rgb': values[4:],
                      'quality': q, 'rgb_usable': q[2:] == '10'}
    if set(rows) != set(range(9)):
        raise ValueError(f'{path}: all nodes 0..8 are required')
    return [rows[n] for n in range(9)]


def span_percent(values):
    return 100 * (max(values) - min(values)) / statistics.mean(values)


def analyze(white, dark=None):
    points = []
    for n, row in enumerate(white):
        raw = row['raw']
        if min(raw) < 64 or max(raw) > 960:
            raise ValueError(f'White node {n}: RAW mean must be 040..3C0; adjust exposure')
        corrected = [v - d for v, d in zip(raw, dark[n]['raw'] if dark else [0]*4)]
        if min(corrected) <= 32:
            raise ValueError(f'Node {n}: insufficient signal after black-level subtraction')
        b, gb, gr, r = corrected
        g = (gb + gr) / 2
        rr, gg, bb = row['rgb']
        rgb_usable = row.get('rgb_usable', True)
        if rgb_usable and (min(rr, gg, bb) < 8 or max(rr, gg, bb) >= 245):
            raise ValueError(f'White node {n}: RGB too dim/clipped for comparison')
        points.append({
            'node': n, 'raw_bggr': raw, 'raw_minus_dark': corrected,
            'quality': row.get('quality', '1010'),
            'rgb_usable': rgb_usable,
            'rgb_before_uniform_brightness': row['rgb'] if rgb_usable else None,
            'raw_r_over_g': r/g, 'raw_b_over_g': b/g, 'raw_gr_over_gb': gr/gb,
            'rgb_r_over_g': rr/gg if rgb_usable else None,
            'rgb_b_over_g': bb/gg if rgb_usable else None,
        })
    spans = {k: span_percent([p[k] for p in points]) for k in
             ['raw_r_over_g', 'raw_b_over_g', 'raw_gr_over_gb',
              'rgb_r_over_g', 'rgb_b_over_g']
             if all(p[k] is not None for p in points)}
    raw_spatial = max(spans['raw_r_over_g'], spans['raw_b_over_g'])
    all_rgb_usable = all(p['rgb_usable'] for p in points)
    rgb_spatial = max(spans['rgb_r_over_g'], spans['rgb_b_over_g']) if all_rgb_usable else None
    # This threshold is an engineering triage aid, not proof of an optical defect.
    if raw_spatial > 5:
        hint = 'Spatial channel-ratio variation exists before ISP; investigate lens/filter/sensor shading.'
    elif rgb_spatial is None:
        hint = 'RAW ratios relatively uniform; RGB completeness failed, so ISP-side comparison is unavailable.'
    elif rgb_spatial > 5:
        hint = 'RAW ratios relatively uniform but RGB ratios vary; investigate ISP/AWB scan behavior/alignment.'
    else:
        hint = 'No >5% spatial ratio span at these nine nodes; investigate global white balance and unsampled regions.'
    return {
        'purpose': 'diagnosis_only_no_correction_applied',
        'bayer_labels_assume_current_BGGR_configuration': True,
        'dark_field_used': dark is not None,
        'all_rgb_usable': all_rgb_usable,
        'rgb_quality_note': None if all_rgb_usable else 'RGB with invalid/clipped Q is excluded. RAW validity is evaluated independently. Do not derive RGB correction gains from these rows.',
        'missing_dark_field_note': None if dark else 'RAW ratios include sensor black-level offsets; obtain a dark field before calculating calibration gains.',
        'span_percent_max_minus_min_over_mean': spans,
        'triage_hint_not_proven_root_cause': hint,
        'requirements': 'Neutral uniform illumination, stationary full-field white/gray, no clipping. Nine points cannot establish the needed calibration mesh density.',
        'points': points,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('white', help='transcribed white-field numeric panel')
    parser.add_argument('--dark', help='optional opaque lens-cap dark-field panel')
    parser.add_argument('--out', required=True, help='diagnostic JSON report')
    args = parser.parse_args()
    try:
        report = analyze(load_panel(args.white), load_panel(args.dark) if args.dark else None)
    except (ValueError, OSError) as exc:
        parser.exit(2, f'ERROR: {exc}\n')
    Path(args.out).write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(report['triage_hint_not_proven_root_cause'])
    print('Saved diagnostic report:', args.out)


if __name__ == '__main__':
    main()
