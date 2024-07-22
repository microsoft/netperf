import json
matrix = json.loads("""{
"env": "azure",
"os": "windows-2022",
"arch": "x64",
"tls": "schannel",
"io": "iocp",
"assigned_pool": "netperf-boosted-windows-pool",
"remote_powershell_supported": "TRUE",
"role": "client",
"env_str": "51773b4f-1965-4994-90de-60b064d88888"
}""")
json_str = json.dumps(matrix).replace('"', '\\"').replace('\n', ' ').replace('\r', ' ')