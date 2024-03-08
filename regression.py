import sqlite3
import json
import statistics

# Connect to the database
conn = sqlite3.connect('netperf.sqlite')
cursor = conn.cursor()

"""

This script updates the regression parameters AFTER a merge / database commit.

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

LAST_N_RUNS = 50 # Only consider results from the last N runs for a particular environment x io x test combination.
# Execute SQL queries to fetch historical data

print("Performing regression analysis to compute upper/lower bounds...")

# REQUIRE: Database has clean data, and Environments table contain comprehensive data.

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
