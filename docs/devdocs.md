
# MsQuic + Netperf "good to know"

- MsQuic maintains a `script/secnetperf.ps1` which assumes its running in the correct context (Our self hosted Github Runner in Netperf). This script does the actual execution of secnetperf in the runner.

- If we want to make an update or adjustment to `secripts/secnetperf.ps1` in MsQuic, follow this flow:

1. Commit your changes to various workflow files in netperf first

2. Push changes on MsQuic

3. Auto-trigger the netperf run from MsQuic

# XDP + Netperf "good to know"

TODO

# eBPF + Netperf "good to know"

TODO
