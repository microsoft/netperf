# Lab Consumption

Write your performance test workflow like:
```yaml
jobs:
    Your_Perf_Job:
        # Currently only windows-2022/ubuntu-20.04 lab runners are available.
        runs-on: [self-hosted, lab, <windows-2022 / ubuntu-20.04>]
        steps:
            - ... # Checkout your project repo...
            - ... # Download your perf tools...
            - ... # Run your perf tests...
            - ... # Collect your perf results...

    attempt-reset-lab:
        name: Attempting to reset lab. Status of this job does not indicate result of lab reset. Look at job details.
        needs: [Your_Perf_Job]
        if: ${{ always() }}
        uses: microsoft/netperf/.github/workflows/schedule-lab-reset.yml@main
        with:
        workflowId: ${{ github.run_id }}
```

This will allow you to run your performance tests on the Netperf lab bench.

State resets between jobs are done on a best-effort basis. See the `Ephemeral Runners` Section in [lab_management.md](lab_management.md) for more details.
