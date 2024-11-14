"""
This script does post-processing of test results, saving them to the database, doing some data cleaning in the meantime.
"""

import sqlite3
import glob
import argparse
import json
import datetime
import os

# Connect to the database
conn = sqlite3.connect('netperf.sqlite')
cursor = conn.cursor()

# Create the parser
parser = argparse.ArgumentParser(description="Process a feature integer.")

# Add an integer argument with a default value
parser.add_argument('--featureint', type=int, default=0, help='An integer number (default: 0).')

# Parse the arguments
args = parser.parse_args()

class Worker:
    def __init__(self, cursor, production=False) -> None:
        self.sql_statements_executed = []
        self.cursor = cursor
        self.production = production
    def execute(self, sql):
        self.sql_statements_executed.append(sql)
        if self.production:
            self.cursor.execute(sql)

    def print_executed_statements(self):
        for sql in self.sql_statements_executed:
            print(sql)
            print('-------------------------------')

print("Dynamically executing SQL from the JSON...")
for json_file_path in glob.glob('*.json'):
    if not os.path.exists(f"{json_file_path}/{json_file_path}"):
        continue
    with open(f"{json_file_path}/{json_file_path}", 'r') as json_file:
        print("Processing file: {}".format(json_file_path))

        # Grab data
        json_content = json_file.read()
        json_obj = json.loads(json_content)
        commit = json_obj["commit"]
        os_version = json_obj["os_version"]
        parts = json_file_path.split("-")
        assert len(parts) >= 8
        io = parts[-1]
        io = io.split(".")[0]
        tls = parts[-2]
        arch = parts[-3]
        os_name_2 = parts[-4]
        os_name_1 = parts[-5]
        os_name = os_name_1 + "-" + os_name_2
        context = parts[-6] # lab / azure

        # Check if Environment table has "SKU" column
        cursor.execute("PRAGMA table_info(Environment)")
        columns = cursor.fetchall()
        sku_column_exists = False
        for column in columns:
            if column[1] == "SKU":
                sku_column_exists = True
                break

        # If it doesn't exists, add the column, and then initailize the data
        if not sku_column_exists:
            print("Extending the Environment table with the SKU column")
            cursor.execute("SELECT * FROM Environment")
            current_env_data = cursor.fetchall()
            cursor.execute("ALTER TABLE Environment ADD COLUMN SKU TEXT")
            for row in current_env_data:
                sku = ""
                if row[4] == "azure":
                    if "windows-2025" in row[1]:
                        sku = "F-Series(4vCPU, 8GiB RAM)"
                    elif "windows-2022" in row[1]:
                        sku = "io=wsk, F-Series(4vCPU, 8GiB RAM). io=iocp,xdp, Experimental_Boost4(4vCPU, 8GiB RAM)"
                    else:
                        sku = "Experimental_Boost4(4vCPU, 8GiB RAM)"
                else:
                    sku = "Dell PowerEdge R650 (80 logical CPUs, 128GB RAM)"
                print(f"Updating row with SKU: {sku}")
                cursor.execute(f"""UPDATE Environment SET SKU = '{sku}' WHERE Environment_ID = {row[0]}""")
            conn.commit()

        if "SKU" not in json_obj:
            # Update Environments table
            cursor.execute(f"""SELECT Environment_ID FROM Environment WHERE Architecture = '{arch}' AND OS_name = '{os_name}' AND OS_version = '{os_version}' AND Context = '{context}'""")
        else:
            cursor.execute(f"""SELECT Environment_ID FROM Environment WHERE Architecture = '{arch}' AND OS_name = '{os_name}' AND OS_version = '{os_version}' AND Context = '{context}' AND SKU = '{json_obj["SKU"]}'""")

        result = cursor.fetchall()

        if len(result) == 0:
            if "SKU" in json_obj:
                new_sku = json_obj["SKU"]
            else:
                if context == "azure":
                    if "windows-2025" in os_name:
                        new_sku = "F-Series(4vCPU, 8GiB RAM)"
                    elif "windows-2022" in os_name:
                        new_sku = "io=wsk, F-Series(4vCPU, 8GiB RAM). io=iocp,xdp, Experimental_Boost4(4vCPU, 8GiB RAM)"
                    else:
                        new_sku = "Experimental_Boost4(4vCPU, 8GiB RAM)"
                else:
                    new_sku = "Dell PowerEdge R650 (80 logical CPUs, 128GB RAM)"
            print('inserting new row with new environment')
            cursor.execute(f"""INSERT INTO Environment (OS_name, OS_version, Architecture, Context, SKU) VALUES ('{os_name}', '{os_version}', '{arch}', '{context}', '{new_sku}')""")
            conn.commit()
            environment_id = cursor.lastrowid
        else:
            print('using existing environment')
            environment_id = result[0][0]
        # print(f"Environment ID: {environment_id}")

        worker = Worker(cursor=cursor, production=True)

        worker.execute(f"""

INSERT OR REPLACE INTO Secnetperf_builds (Secnetperf_Commit, Build_date_time, TLS_enabled, Advanced_build_config)
VALUES ("{commit}", "{datetime.datetime.now()}", 1, "no special configurations.");

        """)

        if not os.path.exists("full_latencies"):
            os.makedirs("full_latencies")

        for testid in json_obj:
            if testid == "commit" or testid == "os_version" or "-lat" in testid or testid == "run_args" or "regression" in testid:
                continue

            # truncate -tcp or -quic from testid
            Testid = testid.split("-")
            transport = Testid.pop()
            Testid = "-".join(Testid)
            extra_arg = " -tcp:1" if transport == "tcp" else " -tcp:0"
            if "run_args" in json_obj:
                run_args = json_obj["run_args"][Testid]
            else:
                run_args = "default_scenario_options"
            worker.execute(f"""
INSERT OR IGNORE INTO Secnetperf_tests (Secnetperf_test_ID, Kernel_mode, Run_arguments) VALUES ("scenario-{testid}", 1, "{run_args + extra_arg}");
            """)

            if "latency" in testid or "rps" in testid:

                full_latency_curve_ids_to_save = {}
                minimum_p0 = float('inf')

                # is a flattened 1D array of the form: [ first run + RPS, second run + RPS, third run + RPS..... ], ie. if each run has 8 values + RPS, then the array has 27 elements (8*3 + 3)
                for offset in range(0, len(json_obj[testid]), 9):
                    p0 = float(json_obj[testid][offset])
                    minimum_p0 = min(minimum_p0, p0)
                    # print(offset)
                    worker.execute(f"""
INSERT INTO Secnetperf_latency_stats (p0, p50, p90, p99, p999, p9999, p99999, p999999)
VALUES ({json_obj[testid][offset]}, {json_obj[testid][offset+1]}, {json_obj[testid][offset+2]}, {json_obj[testid][offset+3]}, {json_obj[testid][offset+4]}, {json_obj[testid][offset+5]}, {json_obj[testid][offset+6]}, {json_obj[testid][offset+7]});
""")
                    last_row_inserted_id = worker.cursor.lastrowid
                    worker.execute(f"""
INSERT INTO Secnetperf_test_runs (Secnetperf_test_ID, Secnetperf_commit, Client_environment_ID, Server_environment_ID, Result, Secnetperf_latency_stats_ID, io, tls, Run_date)
VALUES ("scenario-{testid}", "{commit}", {environment_id}, {environment_id}, {json_obj[testid][offset+8]}, {last_row_inserted_id}, "{io}", "{tls}", "{datetime.datetime.now()}");
""")
                    if testid + "-lat" in json_obj:
                        full_latency_curve_ids_to_save[last_row_inserted_id] = (p0, json_obj[testid + "-lat"][offset // 9])

                for stats_id in full_latency_curve_ids_to_save:
                    p0_val, lat_curve = full_latency_curve_ids_to_save[stats_id]
                    if p0_val == minimum_p0:
                        print(f"Saving full latency curve for {testid} with p0 = {p0_val}")
                        with open(f"full_latencies/full_curve_{stats_id}.json", 'w') as f:
                            json.dump(lat_curve, f)
            else:
                for item in json_obj[testid]:
                    worker.execute(f"""
INSERT INTO Secnetperf_test_runs (Secnetperf_test_ID, Secnetperf_commit, Client_environment_ID, Server_environment_ID, Result, Secnetperf_latency_stats_ID, io, tls, Run_date)
VALUES ("scenario-{testid}", "{commit}", "{environment_id}", "{environment_id}", {item}, NULL, "{io}", "{tls}", "{datetime.datetime.now()}");
""")

        # Commit changes
        conn.commit()

        # dump SQL file for debugging
        # worker.print_executed_statements()

# Close connection
conn.close()
