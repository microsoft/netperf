
# SecNetPerf + Netperf "good to know"

How it works is (WIP),

When a project (MsQuic, Windows Engineering System) calls into netperf to trigger secnetperf tests, they have the option to pass in
a bunch of parameters in the HTTP query. All the files for performance testing relevant to a project is located in that project itself.

The Netperf REST API (Github) options are used to determine which subset of tests to run for secnetperf, how they are run (environment), which build of secnetperf (MsQuic commit) to use... etc.

For instance, some of the arguments are: run on { x64 windows server 2022, arm64? linux ubuntu 20.0.6, x64 rs_onecore_liof_stack1 with version 26013.1000... }, Commit = ..., Run all tests.

(We might consider passing in a JSON / yml as a declarative way to specify the arguments)

To that end, the `.github/secnetperf.yml` workflow will reference a machine exposed by CTS / Azure as a self-hosted Github runner, and use the passed in arguments to configure
the environment(s) and test options for the execution.

In the `secnetperf.yml` script:

It will first determine the environment(s) to run from the arguments, and instruct the CTS/Azure Github Runner to provision and use the right environment(s).

Concurrently, the workflow will build secnetperf with the right commit using re-usable scripts exposed by MsQuic for the various specified environments to be consumed. Upload them as artifacts.

Next, assuming the test environments are configured correctly with the specified OS/version/type, and the artifacts for secnetperf are built and uploaded for the specific environments,
the workflow will enumerate each environment, and in each enumeration:

1. Download the secnetperf artifacts with correct arch and OS

2. Checkout this repository (--branch main)

3. Run `tests/secnetperf/secnetperf.ps1` while passing in any relevant top-level arguments to control which tests we are interested in.

4. Upload the data artifact produced by `secnetperf.ps1` into a known directory on Github Actions, which will be a `.sql` script that we execute later.

After all the enumerations are done, the `secnetperf.yml` workflow will:

1. Checkout this repository with --branch = sqlite

2. Download all the `.sql` artifacts uploaded by the previous enumerations from the known directory

3. Use python to connect to the `netperf.sqlite` database, and execute the downloaded sql files, which should populate the relevant tables.

4. Git commit the modified `netperf.sqlite` file, (we have a cron job periodically erase the history of branch -sqlite to prevent its storage requirements to bloat) and upload to Github artifacts a copy of the `netperf.sqlite` database. Also handles updating the intermediate JSON for the landing page.

Note: `secnetperf.ps1` will be responsible for parsing the console output of running the tests, and saving a `.sql` file.

Note: The dashboard will consume an intermediate JSON file (for performance reasons). The creation / update of this is the final job after saving the data to the database. By default, the triggering project (MsQuic, XDP, windows ES)... can choose to use the current run as the most recent to display
onto the dashboard. Otherwise, they could specify a SQL query for what data they want populated in the intermediate file.

# XDP + Netperf "good to know"

TODO

# eBPF + Netperf "good to know"

TODO
