import sqlite3
import json
import statistics

# Connect to the database
conn = sqlite3.connect('netperf.sqlite')
cursor = conn.cursor()

LAST_N_RUNS = 100 # Only consider results from the last N runs for a particular environment x io x test combination.
# Execute SQL queries to fetch historical data

print("Performing regression analysis to compute upper/lower bounds...")

# REQUIRE: Database has clean data, and Environments table contain comprehensive data.

def compute_baseline(test_run_results, test):
    # Use a statistical approach to compute a baseline.
    """
    test_run_results: [
        ...
        ( Result: REAL, Secnetperf_latency_stats_ID?: *optional, INTEGER)
        ...
    ]

    So if Secnetperf_latency_stats_ID is not NULL, then the test is a latency test, and the Result is RPS.

    TODO: What do we do about latency? Do we have an upper bound threshold for ALL percentiles? Or just a few we choose?

    For computing the baseline of Results (which is ALWAYS a lower bound), we start with a simple approach:

    - Compute the average and subtract 2 standard deviations from the average.
    - For datasets with high variance (but still somewhat normally distributed), this approach is robust enough to be used as a baseline.
    """

    results = [run_result[0] for run_result in test_run_results]
    secnetperf_latency_stats_ids = [run_result[1] for run_result in test_run_results]
    baseline = {
        "baseline" : None
    }
    if secnetperf_latency_stats_ids and secnetperf_latency_stats_ids[0] is not None:
        # TODO: What do we do about computing upper bounds on the latency percentiles for each stats ID? Do we have an upperbound for ALL 50 percentiles? Or just the 8 we store? Or an average?
        baseline["latencyUpperBound"] = "TODO"

    mean = statistics.mean(results)
    if len(results) < 2:
        return {
                "baseline": mean * 0.8,
        }
    else:
        std = statistics.stdev(results)
    lowerbound = mean - 2 * std
    baseline["baseline"] = lowerbound
    return baseline


N = 2 # Number of most recent runs to consider for each environment group.

cursor.execute("SELECT Secnetperf_test_ID, Kernel_mode, Run_arguments FROM Secnetperf_tests")

all_tests = cursor.fetchall()

cursor.execute("SELECT OS_name, Architecture, Context FROM Environment GROUP BY OS_name, Architecture, Context")

environment_groups = cursor.fetchall()

regression_file = {
    testid: {} for testid, _, _ in all_tests
}

for testid, _, _ in all_tests:
    for io in ["wsk", "xdp", "epoll", "rio", "iocp"]:
        for tls in ["openssl", "schannel"]:
           for os_name, arch, context in environment_groups:
                # NOTE: This SQL query makes the implicit assumption that Server environment ID = Client environment ID.
                # If in the future we decide to test scenarios where we have Linux --> Windows... etc, this query will need to change. As well as a lot of our automation YAML as well.
                cursor.execute(
                        f"""
                                SELECT Result, Secnetperf_latency_stats_ID FROM Secnetperf_test_runs
                                        JOIN Environment ON Secnetperf_test_runs.Client_Environment_ID = Environment.Environment_ID
                                                WHERE Secnetperf_test_runs.Secnetperf_test_ID = '{testid}' AND Secnetperf_test_runs.io = '{io}' AND Secnetperf_test_runs.tls = '{tls}' AND Environment.OS_name = '{os_name}' AND Environment.Architecture = '{arch}' AND Environment.Context = '{context}'
                                                        ORDER BY Secnetperf_test_runs.Run_date DESC
                                                                LIMIT {N}
                        """
                )
                data = cursor.fetchall()
                if not data:
                    continue
                regression_file[testid][f"{os_name}-{arch}-{context}-{io}-{tls}"] = compute_baseline(data, testid)

# Save results to a json file.
with open('regression.json', 'w') as f:
    json.dump(regression_file, f, indent=4)

# Close connection
conn.close()
