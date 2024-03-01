# Secnetperf

Restrictions and assumptions:
- Follow test ID semantics: for throughput tests, add "tput-...". For RPS and HPS, add "rps-..." or "hps-..."
- New tests always maps to either throughput, rps, hps. The only differences are the specific run parameters (N connections, Y bytes...)
- Do not specify tcp or quic in the test id. All the testsids have automation to append -tcp:0 or tcp:1 to the test id depending on the scenario.


1. (current: MANUAL) Add a new key-value pair in $allTests in the secnetperf.ps1 script
2. (current: AUTOMATED) Generate updated JSON intermediary file for the new test, both to be used by the dashboard and updating the database.
3. (current: AUTOMATED) Update database with runs of the new test.
4. (current: AUTOMATED) Update regression.py to generate new baseline values for the new test.
5. (current: AUTOMATED) Update generate_historical_data.py to fetch historical data for the new test.
2. (current: MANUAL, goal: AUTOMATED) Update dashboard landing page / detailed pages with data from the new test (show runs and run args.)


# eBPF



# XDP



# Windows

