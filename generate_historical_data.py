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

# throughput_json = {
#     "linuxQuicDownloadThroughput": linuxQuicDownloadThroughput,
#     "linuxQuicUploadThroughput": linuxQuicUploadThroughput,
#     "linuxTcpDownloadThroughput": linuxTcpDownloadThroughput,
#     "linuxTcpUploadThroughput": linuxTcpUploadThroughput,
#     "windowsQuicDownloadThroughput": windowsQuicDownloadThroughput,
#     "windowsQuicUploadThroughput": windowsQuicUploadThroughput,
#     "windowsTcpDownloadThroughput": windowsTcpDownloadThroughput,
#     "windowsTcpUploadThroughput": windowsTcpUploadThroughput
# }

"""
throughput_rps_hps_pages_json = {
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
for test_id, _, run_args in all_secnetperf_tests:
    # HANDLES ALL THROUGHPUT, RPS, HPS RELATED TESTS. 
    for os_name, arch, context in environment_groups:
        for io in ["iocp", "epoll", "wsk", "xdp"]:
            for tls in ["schannel", "openssl"]:
                # NOTE: this query assumes implicitly that client environment ID = server environment ID. 
                # NOTE: If they are different, then we need to re-think our data struct. Perhaps append < client os-arch... > + < server os-arch > in the JSON?
                cursor.execute(f"""
                    SELECT MAX(Result), Secnetperf_test_runs.Secnetperf_commit, OS_version, Build_date_time, Run_date FROM Secnetperf_test_runs
                        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
                            JOIN Environment ON Environment.Environment_ID = Secnetperf_test_runs.Client_environment_ID
                                WHERE OS_name = "{os_name}" AND Architecture = "{arch}" AND Context = "{context}" AND io = "{io}" AND tls = "{tls}" AND Secnetperf_test_ID = "{test_id}"
                                    GROUP BY Secnetperf_test_runs.Secnetperf_commit
                                        ORDER BY Build_date_time DESC, Run_date DESC
                                            LIMIT {HISTORY_LENGTH}
                """)
                data = cursor.fetchall()
                if not data:
                    continue
                env_id_str = f"{os_name}-{arch}-{context}-{io}-{tls}"

                if "tput" in test_id:
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
for test_id, _, run_args in all_secnetperf_tests:
    # HANDLES ONLY TESTS RELATED TO LATENCY
    if "rps" not in test_id: 
        continue 
    for os_name, arch, context in environment_groups:
        for io in ["iocp", "epoll", "wsk", "xdp"]:
            for tls in ["schannel", "openssl"]:
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
                data = cursor.fetchall()
                if not data:
                    continue
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
