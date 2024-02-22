import sqlite3
import json

# Connect to the database
conn = sqlite3.connect('netperf.sqlite')
cursor = conn.cursor()

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

"""

# Read all rows from Environment table from database.

# FOREACH environment row, depending on the specific environment, query for io = [iocp, xdp, rio, wsk], tls = [schannel, openssl].

# Each query nets you the data you use to compute regression metrics.

# Use the queried data and sort based on the test done.

# Now you have a bucket of data for each test.

# Now we use that to run a OLS (ordinary least squares) or compute some average / median and set that as the regression baseline.

# Save all those metrics, for each query done, and commit that to the sqlite branch.

# Close connection
conn.close()
