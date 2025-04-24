# V1


```mermaid
  classDiagram
    class Secnetperf_test_runs {
        Secnetperf_test_ID: TEXT; FOREIGN KEY;
        Secnetperf_commit: TEXT; FOREIGN KEY;
        Client_environment_ID: INTEGER; FOREIGN KEY;
        Server_environment_ID: INTEGER; FOREIGN KEY;
        Secnetperf_latency_stats_ID: INTEGER; FOREIGN KEY;
        Result: REAL;
        io: TEXT;
        tls: TEXT;
        Run_date: TEXT;
    }
    class Environment{
        Environment_ID: INTEGER; PRIMARY KEY; AUTO INCREMENT;
        OS_name: TEXT;
        OS_version: TEXT;
        Architecture: TEXT;
        Context: TEXT;
    }
    class Secnetperf_latency_stats{
        Secnetperf_latency_stats_ID: INTEGER; PRIMARY KEY; AUTO INCREMENT;
        P0: REAL;
        P50: REAL;
        P90: REAL;
        P99: REAL;
        P999: REAL;
        P9999: REAL;
        P99999: REAL;
        P999999: REAL;
    }
    class Secnetperf_builds_table{
        Secnetperf_commit: TEXT; PRIMARY KEY;
        Build_date_time: TEXT;
        TLS_enabled: INTEGER;
        Advanced_build_config: TEXT;
    }

    class Secnetperf_tests {
        Secnetperf_test_ID: TEXT; PRIMARY KEY;
        Kernel_mode: INTEGER;
        Run_arguments: TEXT;
    }

    Environment <|-- Secnetperf_test_runs
    Secnetperf_tests <|-- Secnetperf_test_runs
    Secnetperf_builds_table <|-- Secnetperf_test_runs
    Secnetperf_latency_stats <|-- Secnetperf_test_runs
```

# V2 

The second iteration of the database design includes a Watermark table, that stores the 'best ever' result for each test / environment / io / tls configuration.

The workflow for each run still remains the same, except during the `regression.py` execution phase, we take into account Watermark SQL table. If we expect a regression, a dev can manully tweak the values in the Watermark table.

Because right now, the watermark we compute for `watermark-regression.json` is simply the local max over the last N runs.

```mermaid
  classDiagram
    class Secnetperf_test_runs {
        Secnetperf_test_ID: TEXT; FOREIGN KEY;
        Secnetperf_commit: TEXT; FOREIGN KEY;
        Client_environment_ID: INTEGER; FOREIGN KEY;
        Server_environment_ID: INTEGER; FOREIGN KEY;
        Secnetperf_latency_stats_ID: INTEGER; FOREIGN KEY;
        Result: REAL;
        io: TEXT;
        tls: TEXT;
        Run_date: TEXT;
    }
    class Environment{
        Environment_ID: INTEGER; PRIMARY KEY; AUTO INCREMENT;
        OS_name: TEXT;
        OS_version: TEXT;
        Architecture: TEXT;
        Context: TEXT;
    }
    class Secnetperf_latency_stats{
        Secnetperf_latency_stats_ID: INTEGER; PRIMARY KEY; AUTO INCREMENT;
        P0: REAL;
        P50: REAL;
        P90: REAL;
        P99: REAL;
        P999: REAL;
        P9999: REAL;
        P99999: REAL;
        P999999: REAL;
    }
    class Secnetperf_builds_table{
        Secnetperf_commit: TEXT; PRIMARY KEY;
        Build_date_time: TEXT;
        TLS_enabled: INTEGER;
        Advanced_build_config: TEXT;
    }

    class Secnetperf_tests {
        Secnetperf_test_ID: TEXT; PRIMARY KEY;
        Kernel_mode: INTEGER;
        Run_arguments: TEXT;
    }

    class Secnetperf_watermark {
        Secnetperf_test_ID: TEXT; FOREIGN KEY;
        Client_environment_ID: INTEGER FOREIGN KEY;
        Server_environment_ID: INTEGER FOREIGN KEY;
        BestResultCommit: TEXT FOREIGN KEY;
        BestResult: REAL;
        LastUpdated: TEXT;
    }

    Environment <|-- Secnetperf_test_runs
    Secnetperf_tests <|-- Secnetperf_test_runs
    Secnetperf_builds_table <|-- Secnetperf_test_runs
    Secnetperf_latency_stats <|-- Secnetperf_test_runs
    Secnetperf_watermark <|-- Secnetperf_test_runs
```