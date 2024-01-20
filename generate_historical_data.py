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

# TODO: Secnetperf_test_ID ought to be more transparent. Using order of test results is a bit fragile.
# TODO: Make sure to update these queries when the schema changes.
cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = 2
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 5""")

linuxQuicDownloadThroughput = cursor.fetchall()

cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = 1
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 5""")

linuxQuicUploadThroughput = cursor.fetchall()

cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = 1
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 5""")

linuxTcpDownloadThroughput = cursor.fetchall()

cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = 1
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 5""")

linuxTcpUploadThroughput = cursor.fetchall()

cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = 1
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 5""")

windowsQuicDownloadThroughput = cursor.fetchall()

cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = 1
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 5""")

windowsQuicUploadThroughput = cursor.fetchall()

cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = 1
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 5""")

windowsTcpDownloadThroughput = cursor.fetchall()

cursor.execute("""
    SELECT MAX(Result), Build_date_time, Secnetperf_test_runs.Secnetperf_commit FROM Secnetperf_test_runs
        JOIN Secnetperf_builds ON Secnetperf_builds.Secnetperf_commit = Secnetperf_test_runs.Secnetperf_commit
            WHERE Client_environment_ID = 2 AND Server_environment_ID = 2 AND Secnetperf_test_ID = 1
                GROUP BY Secnetperf_test_runs.Secnetperf_commit
                    ORDER BY Build_date_time DESC
                        LIMIT 5""")

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
latency_json = {}

# Save to disk
with open('throughput.json', 'w') as file:
    json.dump(throughput_json, file, indent=4)

with open('latency.json', 'w') as file:
    json.dump(latency_json, file, indent=4)

conn.close()
