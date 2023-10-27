import json
import os

def is_float(s):
    try:
        float(s)
        return True
    except ValueError:
        return False


class Parse:
    json_data = None
    linux_latency = None
    windows_latency = []
    def __init__(self) -> None:
        curr_dir = os.path.dirname(os.path.abspath(__file__))
        with open(os.path.join(curr_dir, "cpu_data.json"), 'r') as f:
            self.json_data = json.load(f)
        curr_dir += "/RpsLatency/"
        with open(os.path.join(curr_dir, "histogram_RPS_Windows_x64_schannel_Default.txt"), 'r') as f:
            stop_reading = False
            for line in f:
                if stop_reading:
                    break
                if line.startswith('['):
                    stop_reading = True
                else:
                    values = line.split()
                    if len(values) == 4:
                        value, percentile, total_count, reciprocal = values
                        if not is_float(value):
                            continue
                        self.windows_latency.append({
                            'Value': float(value),
                            'Percentile': float(percentile),
                            'TotalCount': int(total_count),
                            'Reciprocal': float(reciprocal),
                        })

if __name__ == "__main__":
    x = Parse()
    print(x.windows_latency[5])
