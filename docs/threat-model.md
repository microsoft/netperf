# Threat Model

## Overview

netperf is a framework and set of tools for measuring network (and related components) performance. It is designed to be used in a controlled environment, with full control over the systems involved in the test. The primary goal of netperf is to provide accurate and repeatable performance measurements.

### Components

#### netperf Repository

The netperf repository contains the scripts and yaml for the netperf framework and tools. It also contains the following secrets, stored in GitHub Respository secrets:

- `AZURE_CLIENT_ID` - Used for accessing the Azure Subscription
- `AZURE_SUBSCRIPTION_ID` - Used for accessing the Azure Subscription
- `AZURE_TENANT_ID` - Used for accessing the Azure Subscription
- `PERSONAL_ACCESS_TOKEN` - Used to access the GitHub CLI
- `VM_PASSWORD` - A well-known password to provision the test machines with

#### GitHub Actions

GitHub Actions is used to run the netperf tests. They use the the yaml, scripts and secrets from the netperf repository to run the jobs necessary to perform the tests. These actions are configured to (securely) remotely triggered via [workflow_call](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#workflow_call), (securely) manually via [workflow_dispatch](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#workflow_dispatch), or via a netperf Pull Request. Pull Request automation from outside contributors **requires explicit approval**.

#### Azure

Some netperf tests are run on Azure Virtual Machines ([details](machines#azure-virtual-machines)). A single Azure Subscription is used for all resources used in Azure. Generally, these resources are dynamically created and destroyed as needed.

#### Lab

Some netperf tests are run on machines in a physical lab ([details](machines#lab-x64-machines)). The lab machines do not have access to any corpnet resources. They have internet access and are on a shared, private network with each other (used for the network testing). The machines are controlled by the netperf framework and are used to run the tests.

#### Dependencies

netperf has dependencies on various other repositories which contain the tools and libraries under test. These dependencies are used to build the tools and libraries and are used in the tests.

## Threat Surface

The following section will focus on threats exposed via netperf itself, and will not cover things like physical security of the lab, or the security of the Azure Subscription beyond what netperf itself exposes.

### Pull Requests

Pull Requests are a primary attack vector for netperf. Pull Requests can trigger the netperf automation to run code to access the Azure Subscription and lab machines. If left unsecured, this could allow an attacker to run arbitrary code on the machines in the lab or in Azure, as well as leverage the Azure Subscription for their own purposes.

This threat is largely mitigated by the following:

1. **Approval Required**: Pull Requests from outside contributors are not automatically run. They must be approved by a netperf maintainer before they will be run. All Pull Requests from outside contributors are thouroughly reviewed before approval.
2. **Secrets**: Secrets are stored in GitHub Secrets and are not exposed in the Pull Request. This means that an attacker would need to compromise the GitHub repository to access the secrets.

Additionally, the Federated credentials that are used to access the Azure Subscription are limited in scope and only allowed to be executed from the main branch of the netperf repository. So, even if a Pull Request were to be run, and somehow get access to the secrets, it would not have access to the Azure Subscription.

### Remote Action Triggering

Since netperf is a framework for other repositories to use, netperf is setup to allow those repositories to remotely trigger netperf's GitHub actions. They do this via [workflow_call](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#workflow_call). A helper has been explicitly created, and you may find more details [here](arch#usage).

The threat of unauthorized access to triggering of the actions is mitigated via general GitHub repository security. Triggers of the GitHub Actions requires write priviliges to netperf. To achieve this requires a token to securely access the netperf repository. In the other repositories, this token is stored in GitHub Secrets and is not directly exposed in the repository, nor to outside Pull Requests. This means that an attacker would need to compromise the repository to access the token. This prevents unauthorized access to the netperf repository.

### Dependencies

netperf has dependencies on other repositories. These repositories are used to build the tools and libraries under test. An attacker could compromise these repositories to inject malicious code into the tools and libraries under test. This could allow an attacker to run arbitrary code on the machines in the lab or in Azure, as well as leverage the Azure Subscription for their own purposes.

These threats are mitigated by only using dependencies from trusted sources. The netperf maintainers are responsible for ensuring that the dependencies are secure and are not compromised. All dependencies are from well known repositories that we also own and enforce similar security practices.
