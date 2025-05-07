import sqlite3
import requests
import os
import json

# Load the sqlite file
# URL of the remote SQLite file
url = 'https://raw.githubusercontent.com/microsoft/netperf/sqlite/netperf.sqlite'

HISTORY_LENGTH = 20

# Check if file already exists

if (os.path.exists('netperf.sqlite')):
    print("File already exists")
else:
    # Download the file
    response = requests.get(url)
    if response.status_code == 200:
        with open('netperf.sqlite', 'wb') as file:
            file.write(response.content)

# Now, open the local copy with sqlite3
conn = sqlite3.connect('netperf.sqlite')
cursor = conn.cursor()

"""
General Shape of data:

    {
        <os>-<arch>-<context>-<io>-<tls> : {
            <testid>: {
                run_args: "...",
                # last N commits, sorted in desc order, choose best out of all runs
                data: [ ... { result: X, os_version: Y, commit: Z, build_date_time: ... } ... ]
            }
        }
        ...
    }

"""

cursor.execute("SELECT OS_name, Architecture, Context FROM Environment GROUP BY OS_name, Architecture, Context")
environment_groups = cursor.fetchall()
cursor.execute("SELECT * FROM Secnetperf_tests")
all_secnetperf_tests = cursor.fetchall()
detailed_throughput_page_json = {}
detailed_rps_page_json = {}
detailed_hps_page_json = {}

def execute_results_query(cursor, os_name, arch, context, io, tls, test_id, HISTORY_LENGTH):
    # NOTE: this query assumes implicitly that client environment ID = server environment ID.
    cursor.execute(f"""
        SELECT MAX(Result), Secnetperf_test_runs.Secnetperf_commit, OS_version, Build_date_time, Run_date FROM Secnetperf_test_runs
            JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
                JOIN Environment ON Environment.Environment_ID = Secnetperf_test_runs.Client_environment_ID
                    WHERE OS_name = "{os_name}" AND Architecture = "{arch}" AND Context = "{context}" AND io = "{io}" AND tls = "{tls}" AND Secnetperf_test_ID = "{test_id}"
                        GROUP BY Secnetperf_test_runs.Secnetperf_commit
                            ORDER BY Build_date_time DESC, Run_date DESC
                                LIMIT {HISTORY_LENGTH}
    """)
    return cursor.fetchall()

def execute_latency_query(cursor, os_name, arch, context, io, tls, test_id, HISTORY_LENGTH):
    # NOTE: Notice the use of MIN(P0) - this is because we only save the full latency curves for the minimum P0 run out of 3 runs.
    cursor.execute(f"""
        SELECT Secnetperf_test_runs.Secnetperf_commit, Secnetperf_test_runs.Secnetperf_latency_stats_ID, OS_version, Build_date_time, Run_date, MIN(P0), P50, P90, P99, P999, P9999, P99999, P999999 FROM Secnetperf_test_runs
            JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
                JOIN Environment ON Environment.Environment_ID = Secnetperf_test_runs.Client_environment_ID
                    JOIN Secnetperf_latency_stats ON Secnetperf_latency_stats.Secnetperf_latency_stats_ID = Secnetperf_test_runs.Secnetperf_latency_stats_ID
                        WHERE OS_name = "{os_name}" AND Architecture = "{arch}" AND Context = "{context}" AND io = "{io}" AND tls = "{tls}" AND Secnetperf_test_ID = "{test_id}"
                            GROUP BY Secnetperf_test_runs.Secnetperf_commit
                                ORDER BY Build_date_time DESC, Run_date DESC
                                    LIMIT {HISTORY_LENGTH}
    """)
    return cursor.fetchall()

requires_archived_throughput_data = False
requires_archived_rps_data = False
requires_archived_hps_data = False
requires_archived_latency_data = False

def generate_tput_rps_hps_pages(cursor, all_secnetperf_tests, environment_groups, use_archive=False):
    global requires_archived_throughput_data
    global requires_archived_rps_data
    global requires_archived_hps_data
    global detailed_throughput_page_json
    global detailed_rps_page_json
    global detailed_hps_page_json
    for test_id, _, run_args in all_secnetperf_tests:

        if use_archive and "scenario" in test_id:
            continue

        if not use_archive and "scenario" not in test_id:
            continue

        for os_name, arch, context in environment_groups:
            for io in ["iocp", "epoll", "wsk", "xdp"]:
                for tls in ["schannel", "openssl", "quictls"]:
                    env_id_str = f"{os_name}-{arch}-{context}-{io}-{tls}"
                    if "download" in test_id or "upload" in test_id or "tput" in test_id:
                        if not requires_archived_throughput_data and use_archive:
                            continue
                        data = execute_results_query(cursor, os_name, arch, context, io, tls, test_id, HISTORY_LENGTH)
                        if not data:
                            continue
                        if len(data) < HISTORY_LENGTH:
                            print("We need more throughput data! Resorting to archive.")
                            requires_archived_throughput_data = True
                        if not env_id_str in detailed_throughput_page_json:
                            detailed_throughput_page_json[env_id_str] = {
                                f"{test_id}" : {
                                    "run_args" : run_args,
                                    "data": data
                                }
                            }
                        else:
                            detailed_throughput_page_json[env_id_str][f"{test_id}"] = {
                                "run_args" : run_args,
                                "data": data
                            }
                    elif "rps" in test_id:
                        if not requires_archived_rps_data and use_archive:
                            continue
                        data = execute_results_query(cursor, os_name, arch, context, io, tls, test_id, HISTORY_LENGTH)
                        if not data:
                            continue
                        if len(data) < HISTORY_LENGTH:
                            print("We need more rps data! Resorting to archive.")
                            requires_archived_rps_data = True
                        if not env_id_str in detailed_rps_page_json:
                            detailed_rps_page_json[env_id_str] = {
                                f"{test_id}" : {
                                    "run_args" : run_args,
                                    "data": data
                                }
                            }
                        else:
                            detailed_rps_page_json[env_id_str][f"{test_id}"] = {
                                "run_args" : run_args,
                                "data": data
                            }
                    elif "hps" in test_id:
                        if not requires_archived_hps_data and use_archive:
                            continue
                        data = execute_results_query(cursor, os_name, arch, context, io, tls, test_id, HISTORY_LENGTH)
                        if not data:
                            continue
                        if len(data) < HISTORY_LENGTH:
                            print("We need more hps data! Resorting to archive.")
                            requires_archived_hps_data = True
                        if not env_id_str in detailed_hps_page_json:
                            detailed_hps_page_json[env_id_str] = {
                                f"{test_id}" : {
                                    "run_args" : run_args,
                                    "data": data
                                }
                            }
                        else:
                            detailed_hps_page_json[env_id_str][f"{test_id}"] = {
                                "run_args" : run_args,
                                "data": data
                            }


detailed_latency_page = {}
def generate_latency_page(cursor, all_secnetperf_tests, environment_groups, use_archive=False):
    global requires_archived_latency_data
    global detailed_latency_page
    for test_id, _, run_args in all_secnetperf_tests:

        if use_archive and "scenario" in test_id:
            continue

        if not use_archive and "scenario" not in test_id:
            continue

        if not requires_archived_latency_data and use_archive:
            continue

        if "latency" not in test_id and "rps" not in test_id:
            continue

        for os_name, arch, context in environment_groups:
            for io in ["iocp", "epoll", "wsk", "xdp"]:
                for tls in ["schannel", "openssl", "quictls"]:
                    data = execute_latency_query(cursor, os_name, arch, context, io, tls, test_id, HISTORY_LENGTH)
                    if not data:
                        continue
                    if len(data) < HISTORY_LENGTH:
                        print("We need more latency data! Resorting to archive.")
                        requires_archived_latency_data = True
                    env_id_str = f"{os_name}-{arch}-{context}-{io}-{tls}"
                    if not env_id_str in detailed_latency_page:
                        detailed_latency_page[env_id_str] = {
                            f"{test_id}" : {
                                "run_args" : run_args,
                                "data": data
                            }
                        }
                    else:
                        detailed_latency_page[env_id_str][f"{test_id}"] = {
                            "run_args" : run_args,
                            "data": data
                        }

generate_tput_rps_hps_pages(cursor, all_secnetperf_tests, environment_groups, use_archive=False)
generate_tput_rps_hps_pages(cursor, all_secnetperf_tests, environment_groups, use_archive=True)
generate_latency_page(cursor, all_secnetperf_tests, environment_groups, use_archive=False)
generate_latency_page(cursor, all_secnetperf_tests, environment_groups, use_archive=True)

# Save to disk
with open('historical_throughput_page.json', 'w') as file:
    json.dump(detailed_throughput_page_json, file)

with open('historical_rps_page.json', 'w') as file:
    json.dump(detailed_rps_page_json, file)

with open('historical_hps_page.json', 'w') as file:
    json.dump(detailed_hps_page_json, file)

with open('historical_latency_page.json', 'w') as file:
    json.dump(detailed_latency_page, file)

conn.close()
