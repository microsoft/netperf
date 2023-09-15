# Network Perfomance Testing

The repo is the common place other Mirosoft owned networking projects (including Windows itself) use to run, store and visualize networking performance testing. Currently, the following projects (will) use this:

- [microsoft/msquic](https://github.com/microsoft/msquic)
- [microsoft/xdp-for-Windows](https://github.com/microsoft/xdp-for-windows)
- [microsoft/ebpf-for-Windows](https://github.com/microsoft/ebpf-for-windows)
- [Windows Server](https://www.microsoft.com/en-us/windows-server/)

## Architecture

![](docs/arch.png)

This repository maintains a GitHub Action for each different test scenario, [quic.yml](./.github/workflows/quic.yml) for MsQuic, that can be triggered by any project with the appropriate access (controlled via PAT).  When a project needs performance testing to be run, it uses the [run-workflow.ps1](./run-workflow.ps1) script to trigger the appropriate test and wait for it to complete.

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow [Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general). Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship. Any use of third-party trademarks or logos are subject to those third-party's policies.
