"""
This script does post-processing of test results, once all the tests have executed and their .sql artifacts are saved and downloaded.
This script will simply connect to the database and execute each sql script. Before each execution, it will do some pre-processing.

Preprocessing of SQL file:
    Because SQL isn't a procedural language, it is difficult to run any control flow logic.
    This is important for us, since in the generated SQL statements, we need to run some
    procedural logic. Specifically, use the file name of the sql file to grab information
    about the plat, os, arch, cpu_type, nic_type, env (lab vs. azure) of the server and client.
    Query our database to see if those configurations already exist, if yes, grab its INTEGER ID
    and replace all placeholders in the generated SQL file with the INTEGER ID. If it does not exist,
    insert a new row in the Environments table, and grab its LAST_ROW_INSERTED_ID() and cache the result
    (you can't cache anything in a pure SQL context, hence why we need to do the preprocessing)
    Currently, server = client, so we only have 1 set of plat,os,arch... in the file name. But
    in the future, if we want to have different environments for client/server, we can encode
    that in the file name and update the pre-processing logic.

You might ask, "all this work to extract Environment ID, why not just scrap environments table and store everything as a friendly string?"
The main benefit is to save space in the database, and allow for additional extensions (adding new metadata).
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

def pre_process_sql_file(filename, filecontent):
    parts = filename.split("-")
    print(parts)
    assert len(parts) >= 8
    io = parts[-1]
    io = io.split(".")[0]
    tls = parts[-2]
    arch = parts[-3]
    os_name_2 = parts[-4]
    os_name_1 = parts[-5]
    os_name = os_name_1 + "-" + os_name_2
    print(os_name)
    context = parts[-6] # lab / azure
    os_version = None
    file = None

    for json_file in glob.glob('*.json'):
        print(json_file)
        if io in json_file and tls in json_file and arch in json_file and os_name in json_file and context in json_file:
            file = json_file
            break
    assert file is not None

    with open(f"{file}/{file}", 'r') as json_file:
        json_content = json_file.read()
        json_obj = json.loads(json_content)
        os_version = json_obj["os_version"]

    cursor.execute(f"""SELECT Environment_ID FROM Environment WHERE Architecture = '{arch}' AND OS_name = '{os_name}' AND OS_version = '{os_version}' AND Context = '{context}'""")
    result = cursor.fetchall()
    if len(result) == 0:
        print('inserting new row with new environment')
        cursor.execute(f"""INSERT INTO Environment (OS_name, OS_version, Architecture, Context) VALUES ('{os_name}', '{os_version}', '{arch}', '{context}')""")
        conn.commit()
        environment_id = cursor.lastrowid
    else:
        print('using existing environment')
        environment_id = result[0][0]
    print(f"Environment ID: {environment_id}")
    filecontent = filecontent.replace("__CLIENT_ENV__", str(environment_id))
    filecontent = filecontent.replace("__SERVER_ENV__", str(environment_id))
    return filecontent

if args.featureint == 2:
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

            # Update Environments table
            cursor.execute(f"""SELECT Environment_ID FROM Environment WHERE Architecture = '{arch}' AND OS_name = '{os_name}' AND OS_version = '{os_version}' AND Context = '{context}'""")
            result = cursor.fetchall()
            if len(result) == 0:
                print('inserting new row with new environment')
                cursor.execute(f"""INSERT INTO Environment (OS_name, OS_version, Architecture, Context) VALUES ('{os_name}', '{os_version}', '{arch}', '{context}')""")
                conn.commit()
                environment_id = cursor.lastrowid
            else:
                print('using existing environment')
                environment_id = result[0][0]
            # print(f"Environment ID: {environment_id}")

            worker = Worker(cursor=cursor, production=True)

            worker.execute(f"""

INSERT OR IGNORE INTO Secnetperf_builds (Secnetperf_Commit, Build_date_time, TLS_enabled, Advanced_build_config)
VALUES ("{commit}", "{datetime.datetime.now()}", 1, "TODO");

            """)

            if not os.path.exists("full_latencies"):
                os.makedirs("full_latencies")

            for testid in json_obj:
                if testid == "commit" or testid == "os_version" or "-lat" in testid or testid == "run_args":
                    continue

                # truncate -tcp or -quic from testid
                Testid = testid.split("-")
                transport = Testid.pop()
                Testid = "-".join(Testid)
                extra_arg = " -tcp:1" if transport == "tcp" else " -tcp:0"
                extra_semantics = "-tcp-1" if transport == "tcp" else "-tcp-0"
                run_args = json_obj["run_args"][Testid]
                testid = Testid + extra_semantics
                worker.execute(f"""
INSERT OR IGNORE INTO Secnetperf_tests (Secnetperf_test_ID, Kernel_mode, Run_arguments) VALUES ("{testid}", 1, "{run_args + extra_arg}");
                """)

                if "rps" in testid:
                    # is a flattened 1D array of the form: [ first run + RPS, second run + RPS, third run + RPS..... ], ie. if each run has 8 values + RPS, then the array has 27 elements (8*3 + 3)
                    for offset in range(0, len(json_obj[testid]), 9):
                        # print(offset)
                        worker.execute(f"""
INSERT INTO Secnetperf_latency_stats (p0, p50, p90, p99, p999, p9999, p99999, p999999)
VALUES ({json_obj[testid][offset]}, {json_obj[testid][offset+1]}, {json_obj[testid][offset+2]}, {json_obj[testid][offset+3]}, {json_obj[testid][offset+4]}, {json_obj[testid][offset+5]}, {json_obj[testid][offset+6]}, {json_obj[testid][offset+7]});
""")
                        last_row_inserted_id = worker.cursor.lastrowid
                        worker.execute(f"""
INSERT INTO Secnetperf_test_runs (Secnetperf_test_ID, Secnetperf_commit, Client_environment_ID, Server_environment_ID, Result, Secnetperf_latency_stats_ID, io, tls, Run_date)
VALUES ("{testid}", "{commit}", {environment_id}, {environment_id}, {json_obj[testid][offset+8]}, {last_row_inserted_id}, "{io}", "{tls}", "{datetime.datetime.now()}");
""")
                        with open(f"full_latencies/full_curve_{last_row_inserted_id}.json", 'w') as f:
                            json.dump(json_obj[testid + "-lat"][offset // 9], f, indent=4)
                else:
                    for item in json_obj[testid]:
                        worker.execute(f"""
INSERT INTO Secnetperf_test_runs (Secnetperf_test_ID, Secnetperf_commit, Client_environment_ID, Server_environment_ID, Result, Secnetperf_latency_stats_ID, io, tls, Run_date)
VALUES ("{testid}", "{commit}", "{environment_id}", "{environment_id}", {item}, NULL, "{io}", "{tls}", "{datetime.datetime.now()}");
""")

            # Commit changes
            conn.commit()

            # dump SQL file for debugging
            # worker.print_executed_statements()



else:
    print("Using the statically downloaded SQL script...")
    # Iterate over all .sql files in the current directory
    for sql_file_path in glob.glob('*.sql'):
        with open(f"{sql_file_path}/{sql_file_path}", 'r') as sql_file:
            print("Processing file: {}".format(sql_file_path))

            sql_script = sql_file.read()

            if args.featureint == 1:
                sql_script = pre_process_sql_file(sql_file_path, sql_script)

            # Execute SQL script
            cursor.executescript(sql_script)

            # Commit changes
            conn.commit()

# Close connection
conn.close()
