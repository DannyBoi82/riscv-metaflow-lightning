import os
import sys
import subprocess

# Check Python version
PYTHON_VERSION = sys.version_info[:2]

def run_subprocess(command, use_input=None):
    # Based on what the students have sourced - I use 3.8 but most students have 3.6.8
    if PYTHON_VERSION >= (3, 7):
        # Python 3.7
        if use_input:
            result = subprocess.run(command, capture_output=True, text=True, input=use_input)
        else:
            result = subprocess.run(command, capture_output=True, text=True)
    else:
        # Python 3.6
        if use_input:
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    universal_newlines=True, input=use_input)
        else:
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    universal_newlines=True)
    return result

def assemble_inputs(directory,command):
    try:
        result = run_subprocess(command)
        if result.stdout:
            print("STDOUT:")
            print(result.stdout)
        if result.stderr:
            print("STDERR:")
            print(result.stderr)
    except Exception as e:
            print(f"Error: {e}")
            return None

def get_golden_sim_res(directory, command):
    try:
        result = run_subprocess(command, use_input="trace\ngo\nquit\n")
        # Print output
        if result.stdout:
            print("STDOUT:")
            print(result.stdout)
        if result.stderr:
            print("STDERR:")
            print(result.stderr)
        print(f"Return code: {result.returncode}")
        return result
    except FileNotFoundError:
        print(f"Error: Directory '{directory}' not found")
        return None
    except Exception as e:
        print(f"Error: {e}")
        return None

def main():
    test_file = sys.argv[1]
    curr_repo = run_subprocess(["git", "rev-parse", "--show-toplevel"]).stdout.strip()
    golden_sim = f"{curr_repo}/447scripts"
    test_dirs = f"{curr_repo}/{test_file}"
    cmd = ["/afs/ece/class/ece447/bin/riscv-ref-sim", f"{test_dirs}"]
    assemble_cmd = ["make", "assemble", f"TEST={test_dirs}"]
    assemble_inputs(curr_repo, assemble_cmd)
    get_golden_sim_res(golden_sim, cmd)

if __name__ == "__main__":
    main()
