# Api interface schema

## What is this?

- The data contract between the backend (that stores all the perf data) and dashboard. It's what the frontend expects.
- Each page would have its own interface.

## How is it implemented?
- Serialized using JSON.
- Served through a REST Api.


## Raw Data Format:

The format of this data is encoded in JSON, but may change if we choose a relational database model.

Also, the specific fields and keys will likely be updated to optimize the access patterns.

Both MsQuic and TCP/TLS uses SecNetPerf for testing, thus the data model for both are similar.


Idea schema:
```
{
    <Protocol / Technology> : {
        <OS + OS metadata> : [
            <test run information>
            ...
        ]
        ...
    }
    ...
}
```
Example:
```
{

    QUIC : {

        # NOTE: I assume information about when an OS was built is encoded in the os metadata.
        #       Thus, to fetch the most recent Windows or Linux build, we can use the JSON key.

        Linux_<os metadata> : [
            {
                Test_Run_On : "12-31-2023",

                Commit : "Commit hash of MsQuic. Left empty for TCP + TLS."

                CPU_Affinity_On : True,

                ...Other Test Run Metadata...

                Connections : [
                    {
                        Streams : [
                            {
                                Events : [
                                    {
                                        Type: "StreamSend",
                                        Start: "<timestamp>",
                                        End: "<timestamp>",
                                        Payload: 1002033 (Number of bytes)
                                    }
                                    ...
                                ]
                            }
                            ...
                        ]
                    }
                    ...
                ]
            }
            ...
        ]

        Windows_<os metadata> : {
            ... same as above ...
        }

        ... more OS flavors ...
    }

    TCP_TLS : {
        ...Schema same as QUIC...
    }

    eBPF : { ... }

    XDP : { ... }
}


{
    "Connections" : [
        {
            "Streams" : [
                {
                    "events" : [
                        {
                            start_timestamp: "...",
                            end_timestamp: "...",
                            bytes_sent: 0,
                            bytes_recv: 1000,
                        }
                    ]
                },

                ...
            ]
        },

        ...
    ]
}

```



Pages based on the mockup design here: [Mockup](https://mockup2.streamlit.app)

### High Level Overview Page (Landing Page)

**GET /overview**

```
{
    "windows" : {
        "arch" : "x64",
        "version" : "11_<windows build>",
        "throughput" : {
            "unit" : "GB / s",
            "QUIC" : {
                "msquic_commit" : "...", # latest commit
                "download" : 10,
                "upload" : 5
            },
            "TCP" : {
                "download" : 5,
                "upload" : 4
                # the TCP version is coupled to the OS version.
            },
        }
        "latency" : {
            "percentiles" : ["p50", "p90", "p99"] # we can add more items here, but 'download' and 'upload' should match.
            "unit" : "ns",
            "QUIC" : {
                "msquic_commit" : "...",
                "download" : [10, 12, 15],
                "upload" : [2, 4, 5],
            },
            "TCP" : {
                "download" : [10, 12, 15],
                "upload" : [2, 4, 5],
                # same reason as above, TCP version coupled with OS version.
            }
        }
    },

    "linux" : {
        ...
        # same as above but data for linux
        ...
    }
}
```

### Detailed Throughput Page

**GET /throughput/QUIC?connections=1 & from=-20 & to=0**

For data about multiple connections, set connections = X > 1.

*from=A, to=B* controls the window in MsQuic's commit history we want to examine.

For example, if *from=-100, to=0*, we will pull data about the last 100 commits from the latest.

If *from=-5, to=-4*, we will pull data about the 5th latest commit, and 4th latest commit.

TODO: Determine if this endpoint is a bit over-engineered.

```
{
    "connections" : 1,
    "commit_range" : [-20, 0]
    "windows" : [
        {
            "arch" : "x64",
            "version" : "11_<windows_build>",
            "msquic_commit" : "...",
            "upload" : 10,
            "download" : 12,
            "unit" : "GB / s"
        }
        ... 19 more items, latest commit at the end of the list.
    ]
    "linux" : [
        {
            "arch" : "x64",
            "version" : "ubuntu_<...>",
            "msquic_commit" : "...",
            "upload" : 10,
            "download" : 12,
            "unit" : "GB / s"
        }
        ...
    ]
}
```

**GET /throughput/TCP/?connections=1**

```
{
    # Very similar to QUIC, but with TCP
    # TODO: we can't really use commits to track progress here, so what do we use? Last N runs?
    # how do we expect to examine / visualize this?
}
```

### Detailed Latency Page

**GET /latency/QUIC/?connections=1 from=-20 & to=0 & percentiles=[p50,p99]**

Set percentiles to get an array for each data point.

```
{
    "connections" : 1,
    "commit_range" : [-20, 0],
    "percentiles" : ["p50", "p99"]
    "windows" : [
        {
            "arch" : "x64",
            "version" : "11_<windows_build>",
            "msquic_commit" : "...",
            "latency" : [10, 512]
            "unit" : "ns"
        }
        ... 19 more items, latest commit at the end of the list.
    ]
    "linux" : [
        {
            "arch" : "x64",
            "version" : "ubuntu_<...>",
            "msquic_commit" : "...",
            "latency" : [15, 678],
            "unit" : "ns"
        }
        ...
    ]
}
```

**GET /latency/TCP/?connections=1 from=-20 & to=0 & percentiles=[p50,p99]**

```
{
    # Very similar to QUIC, but with TCP
    # TODO: we can't really use commits to track progress here, so what do we use? Last N runs?
    # how do we expect to examine / visualize this?
}
```

### Jitter
- TODO

### Datagram loss vs. Throughput
- TODO

### XDP
- TODO

### eBPF
- TODO

### Detailed comparison page
- TODO
