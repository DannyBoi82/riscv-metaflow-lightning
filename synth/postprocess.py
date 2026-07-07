# postprocess.py
#
# SRAM Postprocessor
#
# ECE 18-447
# Carnegie Mellon University
#
# This file is the 18-447 SRAM DC Post Processing script
#
# This python script handles modifying the SRAM timing, power, and area numbers
# to be similar to actual SRAM figures.
#
# Authors:
#   - 2025: Dane Engman and Varun Rajesh

import re
import sys
from pprint import pprint
import math
from datetime import datetime

SRAM_REPORT_FILE = sys.argv[1]
DESIGN_AREA_FILE = sys.argv[2]
DESIGN_POWER_FILE = sys.argv[3]
DESIGN_POWER_HIERARCHY_FILE = sys.argv[4]
DESIGN_TIMING_FILE = sys.argv[5]


def _generate_design_dictionary():

    design_dict = {"riscv_core_timing": {}}

    with open(SRAM_REPORT_FILE, "r") as f:
        file_lines = f.readlines()

        for line in file_lines:
            # r_ports: $num_r_ports; w_ports: $num_w_ports; rw_ports: $num_rw_ports" >> sram.rpt
            dimensions = re.search(r"Design:\s*(\S+);\s*Words:\s*(\d+);\s*Word_Width:\s*(\d+);\s*R_Ports:\s*(\d+);\s*W_Ports:\s*(\d+);\s*RW_Ports:\s*(\d+)", line)
            if dimensions:
                design_name = dimensions.group(1)
                words = int(dimensions.group(2))
                word_width = int(dimensions.group(3))
                r_ports = int(dimensions.group(4))
                w_ports = int(dimensions.group(5))
                rw_ports = int(dimensions.group(6))

                design_dict[design_name] = {
                    "Words": words,
                    "Word_Width": word_width,
                    "R_Ports": r_ports,
                    "W_Ports": w_ports,
                    "RW_Ports": rw_ports,
                }

            count = re.search(r"Design:\s*(\S+);\s*Count:\s*(\d+)", line)
            if count:
                design_name = count.group(1)
                count_value = int(count.group(2))

                design_dict[design_name]["Count"] = count_value

    return design_dict, file_lines


def _parse_report(design_dict, report_text):
    report_type = ""
    current_design = ""
    for line in report_text:
        if line.startswith("Report"):
            report_type = line.split(":")[1].strip()

        if line.startswith("Design"):
            current_design = line.split(":")[1].strip()

        if line.startswith("Combinational area"):
            comb_area = float(line.split(":")[1].strip())
            design_dict[current_design]["Comb Area"] = comb_area

        if line.startswith("Noncombinational area"):
            noncomb_area = float(line.split(":")[1].strip())
            design_dict[current_design]["Noncombinational Area"] = noncomb_area

        if line.startswith("Macro/Black Box area"):
            macro_black_area = float(line.split(":")[1].strip())
            design_dict[current_design]["Macro Black Area"] = macro_black_area

        if line.startswith("Total cell area"):
            total_cell_area = float(line.split(":")[1].strip())
            design_dict[current_design]["Total Cell Area"] = total_cell_area

        if line.startswith("io_pad") \
            or line.startswith("memory") \
            or line.startswith("black_box") \
            or line.startswith("clock_network") \
            or line.startswith("register") \
            or line.startswith("sequential") \
            or line.startswith("combinational") \
            or line.startswith("Total  "):
            parts = line.split("  ")
            parts = [p for p in parts if p != ""]

            group_name = parts[0]
            internal_power = parts[1]
            switching_power = parts[2]
            leakage_power = parts[3]
            total_power = parts[4]

            design_dict[current_design]["Internal Power " + group_name] = float(internal_power.replace("mW", "").strip()) / 1000
            design_dict[current_design]["Switching Power " + group_name] = float(switching_power.replace("mW", "").strip()) / 1000
            design_dict[current_design]["Leakage Power " + group_name] = float(leakage_power.replace("pW", "").strip()) / 1e12
            design_dict[current_design]["Total Power " + group_name] = float(total_power.replace("mW", "").strip()) / 1000

    for design in design_dict   :
        for key in design_dict[design]:
            design_dict[design][key] = float(design_dict[design][key])


def _parse_hierarchical_power_report(design_dict, report_text):
    for line in report_text:
        line = line.strip()

        if line.startswith("timing_model"):
            line_parts = line.split()
            component_name = line_parts[1].replace("(", "").replace(")", "")

            design_dict[component_name]["Total Power Total"] = float(line_parts[5]) / 1000
            design_dict[component_name]["Switching Power Total"] = float(line_parts[2]) / 1000
            design_dict[component_name]["Internal Power Total"] = float(line_parts[3]) / 1000
            design_dict[component_name]["Leakage Power Total"] = float(line_parts[4]) / 1e12


def _remove_sram_fake_area_and_power(design_dict):

    for key in design_dict["riscv_core_timing"]:
        for sram in design_dict:
            if sram != "riscv_core_timing":
                if key in design_dict[sram]:
                    offset = design_dict[sram][key] * design_dict[sram]["Count"]
                    design_dict["riscv_core_timing"][key] -= offset



def _get_clock_period():
    with open(DESIGN_TIMING_FILE, "r") as f:
        count = 0
        for line in f:
            if "clock clk (rise edge)" in line:
                if count == 0:
                    count = 1
                else:
                    return float(line.replace("clock clk (rise edge)", "").split()[0].strip())



def _add_real_sram_area_and_power(design_dict):
    for sram in design_dict:
        if sram != "riscv_core_timing":
            # area calculations
            word_width = design_dict[sram]["Word_Width"]
            words = design_dict[sram]["Words"]
            r_ports = design_dict[sram]["R_Ports"]
            w_ports = design_dict[sram]["W_Ports"]
            rw_ports = design_dict[sram]["RW_Ports"]

            if r_ports == 0 and w_ports == 0 and rw_ports == 1:
                area = word_width * words * 12
            elif r_ports == 1 and w_ports == 1 and rw_ports == 0:
                area = word_width * words * 19.2
            elif r_ports == 1 and w_ports == 0 and rw_ports == 1:
                area = word_width * words * 22.8
            elif r_ports == 0 and w_ports == 0 and rw_ports == 2:
                area = word_width * words * 24
            else:
                print("Unsupported SRAM shape")
                sys.exit(1)

            area *= design_dict[sram]["Count"]

            design_dict["riscv_core_timing"]["Macro Black Area"] += area
            design_dict["riscv_core_timing"]["Total Cell Area"] += area

            # power calculations
            leakage_power = 1.533e-12 * area
            design_dict["riscv_core_timing"]["Leakage Power Total"] += leakage_power
            design_dict["riscv_core_timing"]["Leakage Power memory"] += leakage_power

            # calculate internal power of one SRAM
            if r_ports == 0 and w_ports == 0 and rw_ports == 1:
                min_power = 0.054e-3 * word_width
                internal_power = 12e-3 * word_width * words / (1024 * 8)
            elif r_ports == 1 and w_ports == 1 and rw_ports == 0:
                min_power = 0.066e-3 * word_width
                internal_power = 18e-3 * word_width * words / (1024 * 8)
            elif r_ports == 1 and w_ports == 0 and rw_ports == 1:
                min_power = .073e-3 * word_width
                internal_power = 21.6e-3 * word_width * words / (1024 * 8)
            elif r_ports == 0 and w_ports == 0 and rw_ports == 2:
                min_power = 0.078e-3 * word_width
                internal_power = 25.2e-3 * word_width * words / (1024 * 8)
            else:
                print("Unsupported SRAM shape")
                sys.exit(1)

            internal_power = max(internal_power, min_power)

            # scale dyanmic power w freq
            internal_power = internal_power * 10.0 / _get_clock_period()
            internal_power *= design_dict[sram]["Count"]

            design_dict["riscv_core_timing"]["Internal Power Total"] += internal_power
            design_dict["riscv_core_timing"]["Internal Power memory"] += internal_power

            total_power = internal_power + leakage_power
            design_dict["riscv_core_timing"]["Total Power Total"] += total_power
            design_dict["riscv_core_timing"]["Total Power memory"] += total_power


def _format_area_value(value):
    if value >= 1_000_000:
        return f"{value/1_000_000:.4f} mm²"
    else:
        return f"{value:.4f} μm²"


def _format_power_value(value):
    if value >= 1:
        return f"{value:.4f} W"
    elif value >= 0.001:
        return f"{value*1000:.4f} mW"
    elif value >= 0.000001:
        return f"{value*1000000:.4f} μW"
    elif value >= 0.000000001:
        return f"{value*1000000000:.4f} nW"
    else:
        return f"{value*1000000000000:.4f} pW"


def _generate_reports(data_dict, area_file="area_riscv_core.rpt", power_file="power_riscv_core.rpt"):
    area_report = []
    area_report.append("=" * 50)
    area_report.append("AREA REPORT")
    area_report.append("=" * 50)

    area_keys = ["Comb Area", "Noncombinational Area", "Macro Black Area", "Total Cell Area"]
    for key in area_keys:
        if key in data_dict:
            if key == "Macro Black Area":
                key = "Memory Area"
                area_report.append(f"{key:<30} {_format_area_value(data_dict['Macro Black Area'])}")
            else:
                area_report.append(f"{key:<30} {_format_area_value(data_dict[key])}")


    with open(area_file, 'w', encoding="utf-8") as f:
        f.write(f"Report generated at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write("\n".join(area_report))
        f.write("\n")

    power_report = []
    power_report.append("=" * 50)
    power_report.append("POWER REPORT")
    power_report.append("=" * 50)

    categories = ["io_pad", "memory", "black_box", "clock_network", "register",
                  "sequential", "combinational", "Total"]

    for category in categories:
        power_report.append(f"\n{category.upper()} POWER:")
        power_report.append("-" * 50)
        power_types = ["Internal Power", "Switching Power", "Leakage Power", "Total Power"]
        for power_type in power_types:
            key = f"{power_type} {category}"
            if key in data_dict:
                power_report.append(f"{power_type:<20} {_format_power_value(data_dict[key])}")

    with open(power_file, 'w', encoding="utf-8") as f:
        f.write(f"Report generated at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write("\n".join(power_report))
        f.write("\n")



def main():
    design_dict, sram_report_text = _generate_design_dictionary()
    _parse_report(design_dict, sram_report_text)

    design_area_text = open(DESIGN_AREA_FILE, "r").readlines()
    design_power_text = open(DESIGN_POWER_FILE, "r").readlines()
    design_power_hierarchy_text = open(DESIGN_POWER_HIERARCHY_FILE, "r").readlines()

    _parse_report(design_dict, design_area_text)
    _parse_report(design_dict, design_power_text)

    _parse_hierarchical_power_report(design_dict, design_power_hierarchy_text)

    _remove_sram_fake_area_and_power(design_dict)
    _add_real_sram_area_and_power(design_dict)

    _generate_reports(design_dict["riscv_core_timing"])


if __name__ == "__main__":
    main()
    sys.exit(0)
