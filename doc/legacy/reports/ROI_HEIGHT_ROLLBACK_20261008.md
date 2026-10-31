# ROI height-only rollback (2026-10-08)

The user requested restoration of the prior version except the ROI height-limit fix.

The ISP, top-level wrapper, HDMI mixer, pin constraints, main project and historical synthesis scripts are restored byte-for-byte from sim/build/backup_lsc_20261008.

roi_target_tracker.v is restored from sim/build/backup_roi_20261008 with exactly two changed lines: clamp roi_half_h_candidate against IMG_H - 1 instead of ROI_HALF_H. The width cap, centroid tracking, color detection thresholds, AWB and display brightness retain the original behavior.

Removed LSC sources, key controls, status overlay and their tests are archived in sim/build/rollback_lsc_20261008. Previous color-shading bitstreams are obsolete and must not be used for this rollback.

Validation: eight ModelSim regression groups, including four locked 720p frames of a 180 x 600 red rectangle; FPGA synthesis, route and bit generation. All eight groups passed. Synthesis, route and bit generation passed. Final setup WNS +0.101 ns, hold WNS +0.020 ns; TNS 0 for both. Resource use: 14,844 slices (69.97%), 39 ERAM, 10 DSP.

Deliverable: sim/build/SC520_roi_height_rollback_20261008.bit (1,789,539 bytes). Not automatically flashed to hardware.
