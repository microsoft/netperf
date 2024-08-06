When writing two-machine perf tests for your respective project (MsQuic, XDP, eBPF...), keep in mind:

Netperf supports testing on Azure (via 1ES hosted pools), and our custom on-prem lab (with specialized hardware).

Remote powershell will not always work depending on the environment (1ES pools has limited support for secure node communication).

To help write your network performance testing scripts, add the following lines of YAML to your project workflow file after checking out the netperf repo under the path "netperfrepo" and downloading any necessary artifacts.

```yaml
jobs:
    ...
    prepare-matrix:
        name: Prepare lab matrix, and Azure 1ES matrix.
        uses: microsoft/netperf/.github/workflows/prepare-matrix.yml@main
        with:
            matrix_filename: '<YOUR_PROJECT>.json'
            workflowId: ${{ github.run_id }}
```

```yaml
# References the output of prepare-matrix custom job.

jobs:
    ...
    run-tests-on-azure-infra:
        strategy:
        fail-fast: false
        matrix:
            include: ${{fromJson(needs.prepare-matrix.outputs.azure-matrix)}}
    ...
    run-tests-on-lab-infra:
        strategy:
        fail-fast: false
        matrix:
            include: ${{fromJson(needs.prepare-matrix.outputs.lab-matrix)}}
```

```yaml
# Steps in the "run-tests-on-azure-infra" job

steps:
...
-   name: Start 1ES Machine
    uses: ./netperfrepo/.github/actions/start-1es-machine
    with:
        matrix: '${{ toJson(matrix) }}'
        callback-script: "./netperfrepo/<YOUR_PROJECT>_callback.ps1"
        syncer_secret: ${{ secrets.NETPERF_SYNCER_SECRET }}
        timeout-minutes: 30
...
-   name: Run tests on Azure infra
    run: |
        ./netperfrepo/set-netperf-context.ps1 -Matrix '${{ toJson(matrix) }}' -GithubRunId '${{ github.run_id }}' -SyncerSecret '${{ secrets.NETPERF_SYNCER_SECRET }}'
        Import-Module ./netperfrepo/netperf-lib.psm1

        # Run your Azure testing script now. Remember to use the helpers defined in 'netperf-lib.psm1' to facilitate P2P communication and download any binaries and artifacts beforehand.
...
-   name: Stop 1ES Machine
    uses: ./netperfrepo/.github/actions/stop-1es-machine
    with:
        matrix: '${{ toJson(matrix) }}'
        syncer_secret: ${{ secrets.NETPERF_SYNCER_SECRET }}
```

```yaml
# Steps in the "run-tests-on-lab-infra" job

steps:
...
-   name: Run tests on lab infra
    run: # You can just directly run your test script for the lab. Lab infra relies on remote powershell for copying over binaries and starting / stopping the tests, so your test script will leverage that.
```

### NOTE: In the above example, we split Azure and Lab testing into 2 jobs and 2 test scripts. You can have a single job and test script for your project that runs in both the Azure and Lab environments, but you will have to handle the nuances of each environment (like what we do with MsQuic) within the test script using the context variables. If you prefer this method, then:

```yaml
jobs:
    ...
    run-tests-on-both-infra:
        strategy:
        fail-fast: false
        matrix:
            include: ${{fromJson(needs.prepare-matrix.outputs.full-matrix)}}
        ...
        steps:
            ...
           -    name: Run tests on both infra
                run: |
                    ./netperfrepo/set-netperf-context.ps1 -Matrix '${{ toJson(matrix) }}' -GithubRunId '${{ github.run_id }}' -SyncerSecret '${{ secrets.NETPERF_SYNCER_SECRET }}'
                    Import-Module ./netperfrepo/netperf-lib.psm1

                    # Run your testing script here... Remember to adjust the test script to use the context variables (like $env:netperf_remote_powershell_supported) to handle the nuances of each environment. Using remote powershell when appropriate, and using the netperf-lib functions when remote powershell is not supported.
```

## How do I write my test scripts for Lab infra (only)?

Lab infrastructure only uses remote powershell to facilitate communication between the two machines.

When the step "Run tests on lab infra" executes, by that point, there should be a `"netperf-peer"` trusted host set up on Windows and Linux. Which you can use in your test script to start a remote powershell session with, copy binaries to, and reference in your test tool for your client / server testing tool.

## How do I write my test scripts for Azure (or both Azure and Lab) infra?

Azure 1ES infra does not support reliable remote powershell for Linux + Windows, so you must use netperf's custom solution for peer to peer communication.

When the step "Run tests on Azure infra" executes, it will first load the netperf-lib module and set the necessary context for your test scripts to run.

Your subsequent scripts will have access to context variables like

### Context Variables:

```PowerShell
$env:netperf_remote_powershell_supported = $true | $false
$env:netperf_syncer_secret = "****************************"
$env:netperf_run_id = "***********************************"
$env:netperf_role = "client" | "server"
```

And be able to call functions from netperf-lib.psm1 like

```PowerShell
NetperfSendCommand -Command "START SERVER" # IMPORTANT NOTE: If the command you send will trigger a condition that causes "<YOUR_PROJECT>_callback.ps1" to block,
                                                  # like starting a perf server, your test tool should have a way to get the process to exit gracefully once done.
                                                  # Please note, we have found in manual testing that starting background processes for servers (so it does not block) does not work. (at least for secnetperf)

NetperfWaitServerFinishExecution -UnblockRoutine { ... } -MaxAttempts 30 -WaitPerAttempt 8 # This function will only unblock once <YOUR_PROJECT>_callback.ps1 has finished executing. Use the -UnblockRoutine script block to have the tool-specific code to stop any blocking processes on the server. Please see the above important note.

NetperfSendCommand -Command "DO SOMETHING NON-BLOCKING"
NetperfWaitServerFinishExecution
```

The above are abstraction functions that enable you to communicate and control the peer device without remote powershell, which is restricted in 1ES environments.

And then, `"<YOUR_PROJECT>_callback.ps1"`, which you passed in during the `Start 1ES machine` step, will be executed on the peer device. The script will look something like:

```PowerShell
param(
    [string]$Command
)

if ($Command -eq "START SERVER") {
    # Start a server process... this will cause this script to hang while the server is running.
}

if ($Command -eq "DO SOMETHING NON BLOCKING") {
    # like download and install something...
}
```
