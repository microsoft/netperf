import sqlite3
import requests
import os

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
            GROUP BY Secnetperf_test_runs.Secnetperf_commit
                ORDER BY Build_date_time DESC
                    LIMIT 5""")


results = cursor.fetchall()
print(results)

cursor.execute("SELECT Result, Secnetperf_commit FROM Secnetperf_test_runs LIMIT 5")
results = cursor.fetchall()

conn.close()