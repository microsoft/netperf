## Triggering a netperf Run

The [run-workflow.ps1](../run-workflow.ps1) script is used to trigger the appropriate test and wait for it to complete. The script leverages the [GitHub REST API](https://docs.github.com/en/rest) to trigger the workflow, wait for it to complete and then use the result to pass or fail the original caller.  For example:

```PowerShell
$url = "https://raw.githubusercontent.com/microsoft/netperf/main/run-workflow.ps1"
iex "& { $(irm $url) } ${{ secrets.NET_PERF_TRIGGER }} quic ${{ github.sha }} ${{ github.ref }} ${{ github.event.pull_request.number }}"
```

To call this script, you must have a GitHub Personal Access Token (PAT) with the `public_repo` scope.  This token is stored as a secret in the repository and is passed to the script as the first argument.  The other arguments are the name of the test to run, the SHA of the commit to test, the branch or tag to test, and the pull request number if applicable.

### Running from Another GitHub Repository

Here are a couple explicit steps to onboard a GitHub repo to trigger netperf.

1. Create a new PAT with the `public_repo` scope.
2. Add the PAT as a secret your GitHub repository.
3. Add a step to your workflow to trigger the netperf run. Example:

```yaml
steps:
- name: Run NetPerf Workflow
  shell: pwsh
  run: |
    $url = "https://raw.githubusercontent.com/microsoft/netperf/main/run-workflow.ps1"
    if ('${{ secrets.NET_PERF_TRIGGER }}' -eq '') {
        Write-Host "Not able to run because no secrets are available!"
        return
    }
    iex "& { $(irm $url) } ${{ secrets.NET_PERF_TRIGGER }} quic ${{ github.sha }} ${{ github.ref }} ${{ github.event.pull_request.number }}"
```
