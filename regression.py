import sqlite3
import json

# Connect to the database
conn = sqlite3.connect('netperf.sqlite')
cursor = conn.cursor()

# Execute SQL queries to fetch historical data
secnetperf_regression_file_name = "secnetperf_regression_bounds.json"
secnetperf_regression_stats = {}

# Save the results in a JSON file.
# TODO:
print("Performing regression analysis to compute upper/lower bounds...")

# Close connection
conn.close()
