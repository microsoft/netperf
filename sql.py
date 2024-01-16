import sqlite3
import glob

# Connect to the database
conn = sqlite3.connect('netperf.sqlite')
cursor = conn.cursor()

# Iterate over all .sql files in the current directory
for sql_file_path in glob.glob('*.sql'):
    with open(f"{sql_file_path}/{sql_file_path}", 'r') as sql_file:
        print("Processing file: {}".format(sql_file_path))

        sql_script = sql_file.read()

        # Execute SQL script
        cursor.executescript(sql_script)

        # Commit changes
        conn.commit()

# Close connection
conn.close()
