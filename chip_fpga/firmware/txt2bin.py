import sys
import struct

# 用法: python3 txt2bin.py input.dat output.bin
if len(sys.argv) < 3:
    print("Usage: python3 txt2bin.py <input.dat> <output.bin>")
    sys.exit(1)

input_path = sys.argv[1]
output_path = sys.argv[2]

print(f"Converting {input_path} to binary {output_path}...")

with open(input_path, 'r') as f_in, open(output_path, 'wb') as f_out:
    for line_num, line in enumerate(f_in):
        # 去除空白與換行
        line = line.strip()
        if not line:
            continue
            
        try:
            # 1. 將 16 進位字串 (例如 "FFFFF8E6") 轉成整數
            val = int(line, 16)
            
            # 2. 將整數打包成 4 bytes 的二進位資料
            # '<I' 代表: Little Endian (<), Unsigned Int (I, 4 bytes)
            # RISC-V 是 Little Endian，所以這裡一定要用 <
            binary_data = struct.pack('<I', val & 0xFFFFFFFF)
            
            f_out.write(binary_data)
            
        except ValueError:
            print(f"Error at line {line_num+1}: '{line}' is not valid hex")

print("Conversion done.")