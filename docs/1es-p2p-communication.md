The 2 ways we facilitate peer-to-peer communication to administer 2-machine perf tests is through:

### 1. Remote Powershell
### 2. Shared Cache

---

By default, we prefer remote powershell and use it for lab scenarios.

For 1ES Azure scenarios, we found that remote powershell does not work in Linux environments, and lacks privilege in Windows - limiting behavior. We still try to use remote powershell on Windows, but have to resort to a shared cache service for Linux.

## 1ES Focus

Our goal is to transition all our testing scenarios (lab / Azure) to be controlled and facilitated using 1ES hosted pools.

The main problem here is 1ES does not natively support inter-communication between nodes in the same pool, making it difficult to run 2-machine client / server tests.

## So what?

Our entire netperf project has the abstraction where the testing scripts are owned by the repositories of the product code itself, and we simply provide the infrastructure for facilitating and collecting + dashboarding the results.

As a result, here is our most up-to-date control-flow for running performance tests using 1ES:


![Netperf Architecture](./netperf-arch.png)
