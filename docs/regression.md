# Setting baselines

Since netperf will be run for many many different environments / os / tls / io scenarios, a challenge is figuring out what data to use to compute the baseline.

For instance, we don't wanna use F4 VMs to set the baseline lower bound / upper bound for lab machine data. 

One naive solution is to always use historical data for the the same environment/os/tls/io to compute regression metrics (for example, always use env=lab os=windows-2025, io=iocp, tls=schannel to compute regression baselines for runs of the same combination)

Things get tricky when it comes to windows prerelease builds.

By definition, there won't be historical data on that particular environment/os/io scenario. So should we use Windows Server 2022 run data as our baseline? 

That is why the design for regression baseline generation should be highly configurable, and workflows like quic.yml should be able to specify which baseline they would like to use to see if there is a regression or not. 

