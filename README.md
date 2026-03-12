# Packet Analysis Lab

A network traffic analysis lab built to demonstrate core SOC analyst skills:
passive packet capture, baseline profiling, malicious traffic detection, and
incident reporting.

---

## Lab Environment

| Component | Details |
|-----------|---------|
| Platform | PnetLab Open Edition (KVM) |
| Linux Endpoint | Alpine Linux — 192.168.100.10 |
| Windows Endpoint | Windows 10 — 192.168.100.20 |
| Virtual Switch | Cisco IOU L2 |
| Analysis Host | Arch Linux (Wireshark + tcpdump) |

---

## Documentation

| Phase                                                                                                         | Description                                      | Status     |
| ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ | ---------- |
| [Phase 1 — Environment Setup](Phase%201%20%E2%80%94%20Environment%20Setup.md)                                 | Lab topology, VM configuration, capture pipeline | ✅ Complete |
| [Phase 2 — Baseline Traffic Capture](Phase%202%20—%20Baseline%20Traffic%20Capture.md)                         | Normal traffic generation and capture            | ✅ Complete |
| [Phase 3 — Protocol Deep Dive](Phase%203%20—%20Protocol%20Deep%20Dive.md)                                     | Protocol-level analysis                          | ⏳ Next     |
| [Phase 4 — Malicious Traffic Simulation](Phase%204%20—%20Malicious%20Traffic%20Simulation.md)                 | Attack simulation and capture                    | ⏳ Pending  |
| [Phase 5 — Comparative Analysis](Phase%205%20—%20Comparative%20Analysis%20%28Baseline%20vs%20Malicious%29.md) | Baseline vs malicious comparison                 | ⏳ Pending  |
| [Phase 6 — Reporting](Phase%206%20—%20Reporting.md)                                                           | SOC-style incident report                        | ⏳ Pending  |

## Capture Files

| File             | Size  | Packets | Download                                                                                       |
| ---------------- | ----- | ------- | ---------------------------------------------------------------------------------------------- |
| baseline.pcap.gz | 31 MB | 27,370  | [Phase 2 Release](https://github.com/Souheib-h/Packet-Analysis-Lab/releases/tag/v0.2-baseline) |

---

## Topology

![Topology](assets/images/Topology-Diagram.png)
