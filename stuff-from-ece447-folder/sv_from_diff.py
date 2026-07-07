from pathlib import Path
import re
import sys
from typing import List, Tuple
import subprocess


def parse_register_file(filename: str) -> Tuple[List[str], List[str]]:
    try:
        with open(filename, 'r') as f:
            lines = f.readlines()

        reg_numbers = []
        values = []

        for line_num, line in enumerate(lines, 1):
            line = line.strip()
            if not line:  # Skip empty lines
                continue

            # Split by comma
            parts = line.split(',')

            reg_num = parts[0].strip()
            reg_value = parts[1].strip()

            reg_numbers.append(reg_num)
            values.append(reg_value)

        if not reg_numbers:
            print("Error: No valid register entries found in file")
            sys.exit(1)

        return reg_numbers, values

    except FileNotFoundError:
        print(f"Error: File '{filename}' not found")
        sys.exit(1)
    except Exception as e:
        print(f"Error parsing file: {e}")
        sys.exit(1)

def generate_systemverilog(reg_numbers: List[str], values: List[str], output_filename: str):

    # Name of the package
    package_name = Path(output_filename).stem.split('_')[0]

    # Calculate bit width needed for register names (assuming x0-x31)
    name_width = 5  # 5 bits for 32 registers (0-31)

    value_width = 32

    sv_content = f"""// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
\ttypedef struct packed {{
\t    logic [{name_width-1}:0] name;
\t    logic [{value_width-1}:0] val;
\t}} reg_change_t;

\t// Array of register changes
\treg_change_t changes[{len(reg_numbers)}] = '{{
"""

    # Add each register change
    for i, (reg_num, value) in enumerate(zip(reg_numbers, values)):
        # Add comma except for last element
        comma = "," if i < len(reg_numbers) - 1 else ""

        sv_content += f"\t\t'{{{name_width}'d{reg_num}, {value_width}'h{value[2:]}}}{comma}\n"

    sv_content += "\t};\nendpackage\n"

    # Write to output file
    try:
        with open(output_filename, 'w') as f:
            f.write(sv_content)
        print(f"SystemVerilog file generated: {output_filename}")
    except Exception as e:
        print(f"Error writing output file: {e}")
        sys.exit(1)

def remove_trace():
    try:
        result = subprocess.run(["rm", "-f", "trace.txt"])
        if result.stdout:
            print("STDOUT:")
            print(result.stdout)
        if result.stderr:
            print("STDERR:")
            print(result.stderr)
    except Exception as e:
        print(f"Error: {e}")
        return None


def main():
    if len(sys.argv) != 3:
        print("Usage: python sv_from_diff.py <input_file> <output_file>")
        print("Input file format: each line should contain 'register_number, hex_value'")
        print("Example: 23, 0x000000a")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    # Parse input file
    reg_numbers, values = parse_register_file(input_file)

    # Generate SystemVerilog
    generate_systemverilog(reg_numbers, values, output_file)

    remove_trace()

if __name__ == "__main__":
    main()
