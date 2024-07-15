When writing two-machine test scripts for your respective project (MsQuic, XDP, eBPF...), keep in mind:

Remote powershell will not always work depending on the environment (1ES pools has limited support for secure node communication).

Netperf has a work-around. When running your test scripts, add the netperf-lib.psm1 module and run the set-context.ps1 script to have access to the context.
