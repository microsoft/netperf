# Netperf Release V1

### Requirements
- Robust and reliable performance testing for Azure scenarios
    - 90% success rate minimum. ("success" is defined as no test crashes due to environment conflicts)
- Robust and reliable performance testing for Lab scenarios
    - 90% success rate minimum.

### What needs to be done:

- Stand up the 1ES Azure testing for Windows 2022, Windows Prerelease, Ubuntu 20.04, Ubuntu 22.04 using whatever means to get things functional (~2 weeks)
- Stabilize the static lab machine/VMs to eliminate all the environment errors we're seeing (xdp still running!) (~2 weeks)

# Netperf Release V2

### Requirements
- No dependencies on any 3rd party services to facilitate inter-agent communication within test pools
- Both Azure and Lab testing scenarios fully leverage first-party tools and infrastructure

### What needs to be done:

- Find an alternative communication method that works reliably on both Windows and Linux to execute remote tasks similar to how Remote Powershell functions. (~1 month)
    -  Eliminate any dependency on a 3rd party web service to facilitate inter-agent communication.
- Fully onboard custom hardware lab to 1ES infrastructure (~ 2 months)
    - Eliminate any manual intervention / setup. Get rid of our statitically onboarded lab perf machines/VMs in favor of the hardware pool.