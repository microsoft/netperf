import sqlite3
import requests
import os
import json

# Load the sqlite file
# URL of the remote SQLite file
url = 'https://raw.githubusercontent.com/microsoft/netperf/sqlite/netperf.sqlite'


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
cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = "tput-down-tcp-0"
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 20""")

linuxQuicDownloadThroughput = cursor.fetchall()

cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = "tput-up-tcp-0"
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 20""")

linuxQuicUploadThroughput = cursor.fetchall()

cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = "tput-down-tcp-1"
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 20""")

linuxTcpDownloadThroughput = cursor.fetchall()

cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = "tput-up-tcp-1"
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 20""")

linuxTcpUploadThroughput = cursor.fetchall()

cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = "tput-down-tcp-0"
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 20""")

windowsQuicDownloadThroughput = cursor.fetchall()

cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = "tput-up-tcp-0"
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 20""")

windowsQuicUploadThroughput = cursor.fetchall()

cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = "tput-down-tcp-1"
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 20""")

windowsTcpDownloadThroughput = cursor.fetchall()

cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = "tput-up-tcp-1"
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 20""")

windowsTcpUploadThroughput = cursor.fetchall()

# TODO: Make queries for latency fetches once data gets populated in the automation.



throughput_json = {
    "linuxQuicDownloadThroughput": linuxQuicDownloadThroughput,
    "linuxQuicUploadThroughput": linuxQuicUploadThroughput,
    "linuxTcpDownloadThroughput": linuxTcpDownloadThroughput,
    "linuxTcpUploadThroughput": linuxTcpUploadThroughput,
    "windowsQuicDownloadThroughput": windowsQuicDownloadThroughput,
    "windowsQuicUploadThroughput": windowsQuicUploadThroughput,
    "windowsTcpDownloadThroughput": windowsTcpDownloadThroughput,
    "windowsTcpUploadThroughput": windowsTcpUploadThroughput
}
latency_rps_json = {
    "linuxQuic" : { "env" : 2, "testid" : "rps-up-512-down-4000-tcp-0", "data": [] },
    "linuxTcp": { "env" : 2, "testid" : "rps-up-512-down-4000-tcp-1", "data": [] },
    "windowsQuic": { "env" : 1, "testid" : "rps-up-512-down-4000-tcp-0", "data": [] },
    "windowsTcp": { "env" : 1, "testid" : "rps-up-512-down-4000-tcp-1", "data": [] }
}

for key in latency_rps_json:
    cursor.execute(f"""
        SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit, P0, P50, P90, P99, P999, P9999, P99999, P999999 FROM Secnetperf_test_runs
            JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
                JOIN Secnetperf_latency_stats ON Secnetperf_latency_stats.Secnetperf_latency_stats_ID = Secnetperf_test_runs.Secnetperf_latency_stats_ID
                    WHERE Client_environment_ID = {latency_rps_json[key]["env"]} AND Server_environment_ID = {latency_rps_json[key]["env"]} AND Secnetperf_test_ID = "{latency_rps_json[key]["testid"]}"
                        GROUP BY Secnetperf_test_runs.Secnetperf_commit
                            ORDER BY Build_date_time DESC
                                LIMIT 20""")

    latency_rps_json[key]["data"] = cursor.fetchall()


hps_json = {
    "linuxQuic" : { "env" : 2, "testid" : "hps-conns-100-tcp-0", "data": [] },
    "linuxTcp": { "env" : 2, "testid" : "hps-conns-100-tcp-1", "data": [] },
    "windowsQuic": { "env" : 1, "testid" : "hps-conns-100-tcp-0", "data": [] },
    "windowsTcp": { "env" : 1, "testid" : "hps-conns-100-tcp-1", "data": [] }
}

for key in hps_json:
    cursor.execute(f"""
        SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
            JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
                WHERE Client_environment_ID = {hps_json[key]["env"]}  AND Server_environment_ID = {hps_json[key]["env"]} AND Secnetperf_test_ID = "{hps_json[key]["testid"]}"
                    GROUP BY Secnetperf_test_runs.Secnetperf_commit
                        ORDER BY Build_date_time DESC
                            LIMIT 20""")

    hps_json[key]["data"] = cursor.fetchall()

# Save to disk
with open('detailed_throughput_page.json', 'w') as file:
    json.dump(throughput_json, file, indent=4)

with open('detailed_rps_and_latency_page.json', 'w') as file:
    json.dump(latency_rps_json, file, indent=4)

with open('detailed_hps_page.json', 'w') as file:
    json.dump(hps_json, file, indent=4)


conn.close()
