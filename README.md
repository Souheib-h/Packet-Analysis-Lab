# Packet Analysis Lab

A network traffic analysis lab built to demonstrate core SOC analyst skills:
passive packet capture, baseline profiling, protocol analysis, malicious
traffic detection, and incident reporting.

---

## Lab Environment

| Component | Details |
|-----------|---------|
| Platform | PnetLab Open Edition (KVM) |
| Linux Endpoint | Alpine Linux — 192.168.200.10 |
| Windows Endpoint | Windows 10 — 192.168.200.20 |
| Virtual Switch | Cisco IOU L2 |
| Analysis Host | Arch Linux (Wireshark + tcpdump) |
| Capture Bridge | PnetLab VM — 192.168.122.217 |

> **Note:** The lab subnet was reconfigured from `192.168.100.0/24` to
> `192.168.200.0/24` during Phase 3 to resolve an IP conflict with an
> external Wi-Fi network.

---

## Documentation

| Phase | Description | Status |
|-------|-------------|--------|
| [Phase 1 — Environment Setup](Phase%201%20%E2%80%94%20Environment%20Setup.md) | Lab topology, VM configuration, capture pipeline | ✅ Complete |
| [Phase 2 — Baseline Traffic Capture](Phase%202%20%E2%80%94%20Baseline%20Traffic%20Capture.md) | Normal traffic generation and capture | ✅ Complete |
| [Phase 3 — Protocol Deep Dive](Phase%203%20%E2%80%94%20Protocol%20Deep%20Dive.md) | 8 protocols captured and analyzed: ARP, ICMP, DNS, DHCP, HTTP, FTP, SSH, Traceroute | ✅ Complete |
| [Phase 4 — Malicious Traffic Simulation](Phase%204%20%E2%80%94%20Malicious%20Traffic%20Simulation.md) | Attack simulation and capture | ⏳ Next |
| [Phase 5 — Comparative Analysis](Phase%205%20%E2%80%94%20Comparative%20Analysis%20%28Baseline%20vs%20Malicious%29.md) | Baseline vs malicious comparison | ⏳ Pending |
| [Phase 6 — Reporting](Phase%206%20%E2%80%94%20Reporting.md) | SOC-style incident report | ⏳ Pending |

---

## Capture Files

| File | Phase | Description |
|------|-------|-------------|
| baseline.pcap.gz | Phase 2 | Full baseline session — 27,370 packets |
| phase3_arp.pcapng | Phase 3 | ARP Request/Reply capture |
| phase3_icmp.pcapng | Phase 3 | ICMP Echo Request/Reply capture |
| phase3_dns.pcap | Phase 3 | DNS Query/Response capture |
| phase3_dhcp.pcapng | Phase 3 | DHCP DORA sequence capture |
| phase3_http.pcap | Phase 3 | HTTP GET/Response plaintext capture |
| phase3_ftp.pcap | Phase 3 | FTP control channel — credentials in plaintext |
| phase3_ssh.pcapng | Phase 3 | SSH encrypted session capture |
| phase3_traceroute.pcap | Phase 3 | ICMP TTL path discovery capture |

---

## Topology

![Topology](assets/images/Topology-Diagram.png)

---
