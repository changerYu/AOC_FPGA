#!/usr/bin/env python3
# pack_glb_input.py -- convert a dense 200-byte ECG+RR packet into the 544-word
# tiled GLB input image the EPU actually reads (multi-class demo, M1c).
#
# Reverse-engineered + byte-exact verified against the golden N image
# (hardware/sim/fpga/in.dat). Layout discovered empirically:
#
#   ECG region = words 0..287 (72 rows x 4 words, stride 4):
#     row r in 0..65 : word[4r] = ecg[3r] | ecg[3r+1]<<8 | ecg[3r+2]<<16 | 0x31<<24
#                      (3 ECG uint8 samples in bytes 0..2, byte3 = 0x31)
#     row r in 66..71: word[4r] = 0x31313131   (empty patch rows)
#     the 3 filler words after every row (4r+1,4r+2,4r+3) = 0x31313131
#   words 288..511 = 0x00000000
#   RR region:
#     word 512 = rr[0] | rr[1]<<8 | 0x7F<<16 | 0x7F<<24
#     words 513..543 = 0x7F7F7F7F
#
# Input:  a file with 200 lines, one uint8 hex per line (198 ECG then 2 RR),
#         e.g. <case>/00_glb_input_packet/input_packet_raw.hex from
#         extract_mitdb_one_case_layer_io.py.
# Output: 544 lines, one 32-bit hex word per line (the GLB in.dat / buf image).
#
# Usage:  python3 pack_glb_input.py <raw_200.hex> <out_544.dat>

import sys

NROWS_DATA = 66      # 66 patch rows x 3 = 198 ECG samples
NROWS_TILE = 72      # ECG tile region = 72 rows x 4 words = 288 words
NWORDS     = 544

def build(ecg, rr):
    assert len(ecg) == 198, f"need 198 ECG, got {len(ecg)}"
    assert len(rr) == 2, f"need 2 RR, got {len(rr)}"
    w = [0] * NWORDS
    for r in range(NROWS_TILE):
        base = 4 * r
        if r < NROWS_DATA:
            e0, e1, e2 = ecg[3*r], ecg[3*r+1], ecg[3*r+2]
            w[base] = (e0 & 0xFF) | ((e1 & 0xFF) << 8) | ((e2 & 0xFF) << 16) | (0x31 << 24)
        else:
            w[base] = 0x31313131
        w[base+1] = 0x31313131
        w[base+2] = 0x31313131
        w[base+3] = 0x31313131
    # words 288..511 already 0
    w[512] = (rr[0] & 0xFF) | ((rr[1] & 0xFF) << 8) | (0x7F << 16) | (0x7F << 24)
    for i in range(513, NWORDS):
        w[i] = 0x7F7F7F7F
    return w

def read_raw200(path):
    vals = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                vals.append(int(line, 16) & 0xFF)
    assert len(vals) == 200, f"expected 200 bytes, got {len(vals)}"
    return vals[:198], vals[198:200]

def main():
    if len(sys.argv) != 3:
        print("usage: pack_glb_input.py <raw_200.hex> <out_544.dat>", file=sys.stderr)
        sys.exit(2)
    ecg, rr = read_raw200(sys.argv[1])
    words = build(ecg, rr)
    with open(sys.argv[2], "w") as f:
        for x in words:
            f.write(f"{x:08X}\n")
    print(f"wrote {len(words)} words to {sys.argv[2]}")

if __name__ == "__main__":
    main()
