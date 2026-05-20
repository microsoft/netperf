
For perf client:

1. Configure hardware

a. bcdedit bootdebug
b. enable hyper-v
c. BIOS config
d. set password to never expire
(restart)
e. add physical machine as a self-hosted runner

1.1 Copy VHDX over from RDP.

2. Setup hyper-V VM (CPU/RAM/testsigning enabled)

3. Configure hyper-V VM to be ready for client-server tests

a. set IP addresses, disable defender
b. add client as self-hosted runner
c. set checkpoint as "LATEST"

---

For perf server:

1. Configure hardware

a. bcdedit bootdebug
b. enable hyper-v
c. BIOS config
d. set password to never expire
(restart)
e. add physical machine as a self-hosted runner

1.1 Copy VHDX over from RDP.

2. Setup hyper-V VM (CPU/RAM/testsigning enabled)

3. Configure hyper-V VM to be ready for client-server tests

a. set IP addresses, disable defender
b. set checkpoint as "LATEST"

---

4. Validate

a. Lab reset runs without failure
b. QUIC job on new VM runs without failure
