import sqlite3
import json

# Connect to the database
conn = sqlite3.connect('netperf.sqlite')
cursor = conn.cursor()

LAST_N_RUNS = 100 # Only consider results from the last N runs for a particular environment x io x test combination.
# Execute SQL queries to fetch historical data

print("Performing regression analysis to compute upper/lower bounds...")

# REQUIRE: Database has clean data, and Environments table contain comprehensive data.

"""

 On each secnetperf.ps1 run, the workflow will first download the approriate regression file, and feed that to the secnetperf.ps1 script.
 The secnetperf.ps1 script will then use whatever is in that regression file to decide / detect regressions in new runs.

 The important thing is that data used to compute lower/upper bounds properly reflect the environment and different configurations.

 For example, we don't want to use lab data to determine the metrics for azure data. But even more specific, we don't want to mix io / tls / os as well.

 We really want to produce clean data that's partitioned based on environment / io / os.

 So that means, we must produce as many regression files as we have environment / io / os / tls combinations.

 We could get information about environment (lab / azure), and os data from the database Environment table.

 Then, we could refine a SQL query to find combinations of io / tls.

 Eventually, that should net us a total of around roughly LENGTH(io) * LENGTH(tls) * LENGTH(env) * LENGTH(os) number of regression files generated.

 REQUIREMENT. Number of regression files generated must = whatever number of specific environment / io / tls configurations we are officially testing.

    vec: [
            # Azure Ubuntu 20.04
            { env: "azure", plat: "linux",   os: "ubuntu-20.04", arch: "x64", tls: "openssl",  io: "epoll" },
            # Azure Windows Server 2022
            { env: "azure", plat: "windows", os: "windows-2022", arch: "x64", tls: "schannel", io: "iocp" },
            { env: "azure", plat: "windows", os: "windows-2022", arch: "x64", tls: "schannel", io: "xdp" },
            { env: "azure", plat: "windows", os: "windows-2022", arch: "x64", tls: "schannel", io: "rio" },
            { env: "azure", plat: "windows", os: "windows-2022", arch: "x64", tls: "schannel", io: "wsk" },
            # Azure Windows Server 2025 (preview)
            { env: "azure", plat: "windows", os: "windows-2025", arch: "x64", tls: "schannel", io: "iocp" },
            { env: "azure", plat: "windows", os: "windows-2025", arch: "x64", tls: "schannel", io: "rio" },
            { env: "azure", plat: "windows", os: "windows-2025", arch: "x64", tls: "schannel", io: "xdp" },
            { env: "azure", plat: "windows", os: "windows-2025", arch: "x64", tls: "schannel", io: "wsk" },
            # Lab Windows Server 2022
            { env: "lab",   plat: "windows", os: "windows-2022", arch: "x64", tls: "schannel", io: "iocp" },
            { env: "lab",   plat: "windows", os: "windows-2022", arch: "x64", tls: "schannel", io: "xdp" },
            { env: "lab",   plat: "windows", os: "windows-2022", arch: "x64", tls: "schannel", io: "wsk" },
            # Lab Ubuntu Server 20.04 LTS
            { env: "lab",   plat: "linux",   os: "ubuntu-20.04", arch: "x64", tls: "openssl",  io: "epoll" },
        ]

  NOTE: for windows prerelease builds, os: field will likely be branch name or "prerelease".
"""



"""

TODO:


def compute_baseline(test_run_results, test):
    # TODO: use mahalanobis distance or some other OLS metric to compute baseline.
    # returns: {
    #   "baseline": float,
    #   "lowerbound": boolean
    # }
    return 1

fetch all tests

fetch all environment groups.

Do like a GROUP BY os_version, arch, env and output UNIQUE rows. (remove duplicate rows with the same combination of os_version, arch, env)

for test in all_tests:
    for io in ["wsk", "xdp", "epoll", "rio", "iocp"]:
        for os_version, arch, env in environment_groups: # os version is most important. could be rs_onecore branch name, or something like windows-2025... ubuntu 20.04... etc.
            cursor.execute(
        TODO:

        Do a JOIN from test_runs table and the environment table. Also do a JOIN from test_runs table and secnetperf builds table (for sorting)

        Directly fetch from test_runs table last N most recent runs for each test, io, environment combination. environment is just a basket of relevant variables like {os, arch, env}.

        Partition the run results based on high level environment metrics like {io, tls, os, arch, env}

        )

        relevant runs = cursor.fetchall()

        test_run_results = compute_baseline(relevant_runs, test)

        # TODO: Save test_run_results AND and make it assessible given io, env, arch, os_version, test query metrics. Save all that to a file.


# Save results to a json file.
with open('regression.json', 'w') as f:
    json.dump(results, f)

"""

# cursor.execute("SELECT Secnetperf_test_ID, Kernel_mode, Run_arguments FROM Secnetperf_tests")

# all_tests = cursor.fetchall()

# cursor.execute("SELECT OS_name, Architecture, Context FROM Environment GROUP BY OS_name, Architecture, Context")

# environment_groups = cursor.fetchall()

# for testid, _, _ in all_tests:
#     for io in ["wsk", "xdp", "epoll", "rio", "iocp"]:
#         for tls in ["openssl", "schannel"]:
#            for os_version, arch, context in environment_groups:
#                 # NOTE: This SQL query makes the implicit assumption that Server environment ID = Client environment ID.
#                 # If in the future we decide to test scenarios where we have Linux --> Windows... etc, this query will need to change. As well as a lot of our automation YAML as well.
#                 cursor.execute(
#                         f"""
#                                 SELECT * FROM Secnetperf_test_runs
#                                         JOIN Environment ON Secnetperf_test_run.Client_Environment_ID = Environment.Environment_ID
#                                                 WHERE Secnetperf_test_runs.Secnetperf_test_ID = {testid} AND Secnetperf_test_runs.io = '{io}' AND Environment.OS_name = '{os_version}' AND Environment.Architecture = '{arch}' AND Environment.Context = '{context}'
#                                 ... TODO ...
#                         """
#                 )
# Close connection
conn.close()
