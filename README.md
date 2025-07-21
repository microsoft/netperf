# Network Perfomance Testing

The repo is the common place other Microsoft owned open source networking projects use to run, store and visualize networking performance testing. Currently, the following projects (will) use this:

- [microsoft/msquic](https://github.com/microsoft/msquic) -- [Dashboard](https://microsoft.github.io/netperf/dist) (actively running per PR on Netperf)
- [microsoft/xdp-for-Windows](https://github.com/microsoft/xdp-for-windows) -- (not supported yet)
- [microsoft/ebpf-for-Windows](https://github.com/microsoft/ebpf-for-windows) -- [Dashboard](https://bpfperformancegrafana.azurewebsites.net/public-dashboards/3826972d0ff245158b6df21d5e6868a9?orgId=1) (running on a schedule)

## Goal

Historically, networking performance testing has been spotty, inconsistent, not reproducable, and not easily accessible.  Different groups or projects test performance in different ways, on different hardware.  They even have different definitions of things like throughput and latency.  This repo aims to fix that by providing a common, open place to run, store, and visualize networking performance testing.  The end result is ultimately a set of dashboards summarizing the performance of the various projects, across various scenarios, and across various platforms.

## Documentation

- [Start Here](./docs/start_here.md)

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow [Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general). Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship. Any use of third-party trademarks or logos are subject to those third-party's policies.
