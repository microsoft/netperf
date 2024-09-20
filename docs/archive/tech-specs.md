## What is this?

This document details the current way we run our network performance tests. Whereas `arch.md` goes over the
high level details of how the pieces fit together, this document dives into the nitty-gritty technical details of how we implement and support the functionality in `arch.md`.

## Requirements

Our scenario involves testing the network performance of MsQuic, ebpf-for-windows, and xdp-for-windows, across a variety of operating systems (Windows prerelease builds included), environments (Azure / custom lab), and IO configurations.

**Most, if not all our tests requires a client and server.**


This means we need to have a good solution for quickly spinning up a pair of test-ready VMs ready to talk to each other.

A VM is **test-ready** when you can launch an installed version powershell 7 on it and be able to start a remote powershell session to its "netperf-peer." The "netperf-peer" is the other VM this VM is assigned to. The "client" of the pair drives the tests.

Our solution should make it easy to specify the OS (windows prerelease build, windows-2022, linux...etc.) for all environments (Azure / Linux).

Our solution should use temporary VMs, to avoid having to deal with any residual artifacts from previous tests and jobs.


## Architecture Design (As of 4/19/2024)

### Testing on Azure

Currently, netperf uses Github Actions automation to kick off a workflow that calls into the Azure Powershell CLI to dynamically create N pairs of temporary Azure VMs.

We orchestrate everything with Powershell, which makes it possible to query the IP addresses of the VMs we created and remotely run powershell commands to setup each VM with it's "netperf-peer" (see Requirements if this is unclear) and make that VM **test-ready**.

After we run the remote-powershell scripts, the **test-ready** clients are added to the pool of Github Actions self-hosted runners and assigned a tag that we reference later in the pipeline to run jobs and tests on them.

We also have management-scripts that load-balance and deletes residual VMs and runners if they are not in-use.

If any VMs fail to be created or onboarded to be **test-ready**, we reassign the jobs supposed to run on those VMs to healthy **test-ready** VMs with the same Operating System and environment.

That is how we do Azure testing today with "temporary" VMs.

### Testing in Lab

In our lab, we set the requirement of 1 VM per host. That means for our tests, we need at least 2 physical hosts.

We manually onboarded Windows 2022 VMs on 2 of our lab machines that we hand-picked. We added the "client" Windows 2022 VM as a self-hosted Github runner with some tags we assigned ourselves. We did the same with Ubuntu 20.04.

Whenever we need to run lab tests, our Github Actions workflow runs will reference the static VMs we added.

This means we're using the same lab VMs across multple jobs / test runs. This is bad practice and leads us to having to deal with a lot of garbage collection issues.


## Ideas for the immediate future

### Testing on Azure
The system we have right now for handling temporary VMs is good enough for now. We need to expand this to Windows prerelease builds and Ubuntu.

### Testing in Lab
One idea is to add the Physical host as a self-hosted Github runner, and run scripts / DPT (custom command line tools) to dynamically provision lab VMs that we use.

It will be a system very similar to Azure VMs, where we will do some tag manipulation to add robustness.


## What we hope to strive for

### Testing on Azure

We don't need to worry about infrastructure.

Either 1ES hosted pool or CloudTest can worry about  giving us the resources per job (2 **test-ready** VMs) and we can just reference them in our Github Actions workflow.

### Testing in Lab

We don't need to worry about infrastructure.

Either 1ES hosted pool or CloudTest can worry about  giving us the resources per job (2 **test-ready** VMs) and we can just reference them in our Github Actions workflow.

