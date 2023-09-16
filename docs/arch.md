# Architecture

![](arch.png)

This repository maintains a GitHub Action for each different test scenario, [quic.yml](./.github/workflows/quic.yml) for MsQuic, that can be triggered by any project with the appropriate access (controlled via PAT).  When a project needs performance testing to be run, it uses the [run-workflow.ps1](./run-workflow.ps1) script to trigger the appropriate test and wait for it to complete.