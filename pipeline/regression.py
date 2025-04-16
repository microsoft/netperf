import sqlite3
import json
import statistics
import argparse
import glob
import os

# Create the parser
parser = argparse.ArgumentParser(description="Process a feature integer.")

# Add an integer argument with a default value
parser.add_argument('--featureint', type=int, default=1, help='An integer number (default: 1).')

# Parse the arguments
args = parser.parse_args()

# Connect to the database
conn = sqlite3.connect('netperf.sqlite')
cursor = conn.cursor()

"""

This script updates the regression parameters AFTER a merge / database commit.

Singlular datapoint method (featureint == 1)
    Brief.
    We store the watermark result in our database.
    On each new run, we grab the JSON results, and compare that against what we have in the database.


Sliding window method (featureint == 2)
    Brief.
    Watermark-based regression:
        ASSUME that the latest run has already been committed to the database.
        We maintain the best result we have seen thus far, and a 'noise' component (0 - 1).
        We fail a run if the new result is < the best result * (1 - noise) or > the best result * (1 + noise).
        The structure of watermark json looks like:
        {
            <testid>-<transport> {
                <environment str> : {

                    "BestResult": number
                    "BestResultCommit": string
                    "Noise": number
                    "baseline": BestResult * (1 - noise)

                    "LatencyUpperBound" : {

                        # TODO: not exactly sure what watermark for latencies should be.

                        # For instance, do we use the minimum of EACH respective column?
                        # That would mean the newest run wouldn't compare against ONE best run in the past, but potentially THREE best runs (MIN(P0), MIN(P50), MIN(P99))
                        # Not sure which is the way to go, so just re-use the MEAN - STD model here.

                        "P0" : MEAN( last N runs P0 column ) + STD( last N runs P0 column )
                        "P50" : MEAN( last N runs ... ) + STD( last N runs ... )
                        "P99" : MEAN( last N runs ... ) + STD( last N runs ... )
                    }
                }
            }
        }
    Mean - Standard Deviation regression:
        Similar to watermark-based, except instead of storing BestResult, we store Mean(last N runs) +- STD(last N runs),
        and use that as our baseline.
"""

print("Performing regression analysis to compute upper/lower bounds...")

# REQUIRE: Database has clean data, and Environments table contain comprehensive data.
def singular_datapoint_method():
    global conn
    global cursor
    """
    NOTE: For this method, we are not recording a "best ever" latency result as it's unclear how we should compare 2 distributions.
    Who is to say one distrobution with a lower P0 but a higher P99 is better than another?
    """
    NOISE = 0.3 # We allow future runs to be 30% less than the best-ever result.

    watermark_regression_file = {}
    for json_file_path in glob.glob('*.json'):
        if not os.path.exists(f"{json_file_path}/{json_file_path}"):
            continue

        with open(f"{json_file_path}/{json_file_path}", 'r') as json_file:
            print("Processing file: {}".format(json_file_path))
            # Grab data
            json_content = json_file.read()
            json_obj = json.loads(json_content)
            parts = json_file_path.split("-")
            assert len(parts) >= 8
            commit = json_obj["commit"]
            io = parts[-1]
            io = io.split(".")[0]
            tls = parts[-2]
            arch = parts[-3]
            os_name_2 = parts[-4]
            os_name_1 = parts[-5]
            os_name = os_name_1 + "-" + os_name_2
            context = parts[-6] # lab / azure
            for testid in json_obj:
                if testid == "commit" or testid == "os_version" or "-lat" in testid or testid == "run_args" or "regression" in testid:
                    continue

                env_str = f"{os_name}-{arch}-{context}-{io}-{tls}"

                if "rps" in testid:
                    # NOTE: We are ignoring the percentiles and only considering requests per second because we don't have a way to compare 2 distributions.
                    result = json_obj[testid] # Looks like [p0, p50 ... RPS, p0, p50, ... RPS], where RPS is every 9th element.
                    new_result_avg = sum([int(result) for result in result[8::9]]) / len(result[8::9]) # [8::9] grabs every 9th element starting from the 9th element.
                else:
                    new_result_avg = sum([int(result) for result in json_obj[testid]]) / len(json_obj[testid])
                cursor.execute(f"""
                    SELECT BestResult, BestResultCommit FROM Secnetperf_tests_watermark WHERE Secnetperf_test_ID = '{testid}' AND environment = '{env_str}'
                """)
                bestever = new_result_avg
                bestever_commit = commit
                watermark_so_far = cursor.fetchall()
                if not watermark_so_far:
                    cursor.execute(f"""
                        INSERT INTO Secnetperf_tests_watermark (Secnetperf_test_ID, environment, BestResult, BestResultCommit) VALUES ('{testid}', '{env_str}', {new_result_avg}, '{bestever_commit}')
                    """)
                    conn.commit()
                else:
                    bestever_result = watermark_so_far[0][0]
                    best_commit_so_far = watermark_so_far[0][1]
                    if float(new_result_avg) > float(bestever_result):
                        cursor.execute(f"""
                            UPDATE Secnetperf_tests_watermark SET BestResult = {new_result_avg}, BestResultCommit = '{bestever_commit}' WHERE Secnetperf_test_ID = '{testid}' AND environment = '{env_str}'
                        """)
                        conn.commit()
                    else:
                        bestever = bestever_result
                        bestever_commit = best_commit_so_far

                if testid not in watermark_regression_file:
                    watermark_regression_file[testid] = {}

                watermark_regression_file[testid][env_str] = {
                    "BestResult": bestever,
                    "Noise": NOISE,
                    "baseline": bestever * (1 - NOISE),
                    "BestResultCommit": bestever_commit
                }

        with open('watermark_regression.json', 'w') as f:
            json.dump(watermark_regression_file, f, indent=4)

def compute_baseline_watermark(test_run_results, test):
    # Use a statistical approach to compute a baseline.
    """
    test_run_results: [
        ...
        ( Result: REAL, Secnetperf_latency_stats_ID?: *optional, INTEGER)
        ...
    ]

    So if Secnetperf_latency_stats_ID is not NULL, then the test is a latency test, and the Result is RPS.
    For computing the baseline of Results (which is ALWAYS a lower bound), we start with a simple approach:

    - Compute the average and subtract 2 standard deviations from the average.
    - For datasets with high variance (but still somewhat normally distributed), this approach is robust enough to be used as a baseline.
    """

    baseline = {
        "baseline" : None
    }
    if "rps" in test:
        try:
            p0 = [run_result[2] for run_result in test_run_results]
            p50 = [run_result[3] for run_result in test_run_results]
            p99 = [run_result[4] for run_result in test_run_results]

            p0UpperBound = statistics.mean(p0) + 3 * statistics.stdev(p0)
            p50UpperBound = statistics.mean(p50) + 3 * statistics.stdev(p50)
            p99UpperBound = statistics.mean(p99) + 3 * statistics.stdev(p99)

            baseline["latencyUpperBound"] = {
                "P0": p0UpperBound,
                "P50": p50UpperBound,
                "P99": p99UpperBound
            }
        except:
            print("Fatal error, expected P0, P50, P99 columns in test_run_results")

    max_result = 0
    max_result_commit = None

    for result in test_run_results:
        Result = result[0]
        commit = result[1]
        if Result > max_result:
            max_result = Result
            max_result_commit = commit

    baseline["BestResult"] = max_result
    baseline["BestResultCommit"] = max_result_commit
    baseline["Noise"] = 0.2 # TODO: Once we aggregate enough data, we should run tests to see what is the tightest bound here. And build a more robust infra to change / invalidate this.
    baseline["baseline"] = max_result * (1 - baseline["Noise"])
    return baseline

def compute_baseline(test_run_results, test):
    # Use a statistical approach to compute a baseline.
    """
    test_run_results: [
        ...
        ( Result: REAL, Secnetperf_latency_stats_ID?: *optional, INTEGER)
        ...
    ]

    So if Secnetperf_latency_stats_ID is not NULL, then the test is a latency test, and the Result is RPS.
    For computing the baseline of Results (which is ALWAYS a lower bound), we start with a simple approach:

    - Compute the average and subtract 2 standard deviations from the average.
    - For datasets with high variance (but still somewhat normally distributed), this approach is robust enough to be used as a baseline.
    """

    results = [run_result[0] for run_result in test_run_results]
    baseline = {
        "baseline" : None
    }
    if "rps" in test:
        # Compute upper bound for RPS as well.
        try:
            p0 = [run_result[2] for run_result in test_run_results]
            p50 = [run_result[3] for run_result in test_run_results]
            p99 = [run_result[4] for run_result in test_run_results]

            p0UpperBound = statistics.mean(p0) + 3 * statistics.stdev(p0)
            p50UpperBound = statistics.mean(p50) + 3 * statistics.stdev(p50)
            p99UpperBound = statistics.mean(p99) + 3 * statistics.stdev(p99)

            baseline["latencyUpperBound"] = {
                "P0": p0UpperBound,
                "P50": p50UpperBound,
                "P99": p99UpperBound
            }
        except:
            print("Fatal error, expected P0, P50, P99 columns in test_run_results")
    mean = statistics.mean(results)
    if len(results) < 2:
        baseline["baseline"] = mean * 0.5
        return baseline
    else:
        std = statistics.stdev(results)
    lowerbound = mean - 3 * std
    baseline["baseline"] = lowerbound
    return baseline

def sliding_window():
    global conn
    global cursor

    N = 20 # Number of most recent commit results to consider for each environment group.

    cursor.execute("SELECT Secnetperf_test_ID, Kernel_mode, Run_arguments FROM Secnetperf_tests")

    all_tests = cursor.fetchall()

    cursor.execute("SELECT OS_name, Architecture, Context FROM Environment GROUP BY OS_name, Architecture, Context")

    environment_groups = cursor.fetchall()

    regression_file = {
        testid: {} for testid, _, _ in all_tests
    }

    watermark_regression_file = {
        testid: {} for testid, _, _ in all_tests
    }

    for testid, _, _ in all_tests:
        for io in ["wsk", "xdp", "epoll", "rio", "iocp"]:
            for tls in ["openssl", "schannel"]:
                for os_name, arch, context in environment_groups:
                        # NOTE: This SQL query makes the implicit assumption that Server environment ID = Client environment ID.
                        # If in the future we decide to test scenarios where we have Linux --> Windows... etc, this query will need to change. As well as a lot of our automation YAML as well.

                        if "rps" in testid:
                            # Rows fetched guaranteed to have latency results
                            cursor.execute(
                                    f"""
                                            SELECT AVG(Result), Secnetperf_test_runs.Secnetperf_commit, AVG(P0), AVG(P50), AVG(P99) FROM Secnetperf_test_runs
                                                JOIN Secnetperf_latency_stats ON Secnetperf_test_runs.Secnetperf_latency_stats_ID = Secnetperf_latency_stats.Secnetperf_latency_stats_ID
                                                    JOIN Environment ON Secnetperf_test_runs.Client_Environment_ID = Environment.Environment_ID
                                                        JOIN Secnetperf_builds ON Secnetperf_test_runs.Secnetperf_commit = Secnetperf_builds.Secnetperf_commit
                                                            WHERE Secnetperf_test_runs.Secnetperf_test_ID = '{testid}' AND Secnetperf_test_runs.io = '{io}' AND Secnetperf_test_runs.tls = '{tls}' AND Environment.OS_name = '{os_name}' AND Environment.Architecture = '{arch}' AND Environment.Context = '{context}'
                                                                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                                                                    ORDER BY Build_date_time DESC, Secnetperf_test_runs.Run_date DESC
                                                                        LIMIT {N}
                                    """
                            )
                        else:
                            cursor.execute(
                                    f"""
                                            SELECT AVG(Result), Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
                                                JOIN Environment ON Secnetperf_test_runs.Client_Environment_ID = Environment.Environment_ID
                                                    JOIN Secnetperf_builds ON Secnetperf_test_runs.Secnetperf_commit = Secnetperf_builds.Secnetperf_commit
                                                        WHERE Secnetperf_test_runs.Secnetperf_test_ID = '{testid}' AND Secnetperf_test_runs.io = '{io}' AND Secnetperf_test_runs.tls = '{tls}' AND Environment.OS_name = '{os_name}' AND Environment.Architecture = '{arch}' AND Environment.Context = '{context}'
                                                            GROUP BY Secnetperf_test_runs.Secnetperf_commit
                                                                ORDER BY Build_date_time DESC, Secnetperf_test_runs.Run_date DESC
                                                                    LIMIT {N}
                                    """
                            )
                        data = cursor.fetchall()
                        if not data:
                            continue
                        regression_file[testid][f"{os_name}-{arch}-{context}-{io}-{tls}"] = compute_baseline(data, testid)
                        watermark_regression_file[testid][f"{os_name}-{arch}-{context}-{io}-{tls}"] = compute_baseline_watermark(data, testid)

    # Save results to a json file.
    with open('regression.json', 'w') as f:
        json.dump(regression_file, f, indent=4)

    with open('watermark_regression.json', 'w') as f:
        json.dump(watermark_regression_file, f, indent=4)

    # Close connection
    conn.close()

if args.featureint == 1:
    singular_datapoint_method()
elif args.featureint == 2:
    sliding_window()
else:
    print("Method not supported.")