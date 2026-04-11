# Phase 3 — Protocol Deep Dive

> **Note:** Following Phase 2, the lab subnet was reconfigured from `192.168.100.0/24` to `192.168.200.0/24`, and the PnetLab VM address updated from `192.168.122.196` to `192.168.122.217`, to resolve an IP conflict with an external Wi-Fi network. All captures and configurations from this phase onwards reflect the updated addressing.

---

## A) Protocols Selected

|#|Protocol|Layer|Purpose|SOC Relevance|
|---|---|---|---|---|
|1|ARP|L2|MAC/IP resolution|ARP spoofing, cache poisoning|
|2|ICMP|L3|Reachability / diagnostics|Ping sweeps, tunneling, floods|
|3|DNS|L7|Name resolution|Exfiltration, spoofing, C2 beaconing|
|4|DHCP|L7|IP assignment|Rogue DHCP server, starvation|
|5|HTTP|L7|Web traffic (plaintext)|Credential sniffing, injection|
|6|FTP|L7|File transfer (plaintext)|Credential exposure|
|7|SSH|L7|Encrypted remote access|Brute force detection|
|8|Traceroute|L3|Path discovery|Network reconnaissance|

---

## B) Protocol Analysis

---

### 1. ARP — Address Resolution Protocol

#### Concept

Every device on a network has two addresses: an **IP address** (logical, used for routing) and a **MAC address** (physical, used to actually deliver a frame on the local network). ARP is the protocol that bridges the two — it answers the question _"I know the IP of who I want to talk to, but what is their MAC address?"_

When a device wants to communicate with another on the same subnet, it sends an **ARP Request** as a broadcast — meaning every device on the network receives it. The message is essentially: _"Who has IP x.x.x.x? Tell me your MAC."_ Only the device that owns that IP responds with an **ARP Reply**, sent directly (unicast) back to the requester. The result is stored in the **ARP cache** of the requesting machine to avoid repeating the process for every packet.

```
[Alpine - 192.168.200.10]
        |
        | ARP Request (broadcast → ff:ff:ff:ff:ff:ff)
        | "Who has 192.168.200.20? Tell 192.168.200.10"
        |
   [IOU L2 Switch] ──────────────────────────────────────────────┐
        |                                                          |
        |                                               [Windows - 192.168.200.20]
        |                                                          |
        | ◄─────────────────────────────────────────────────────── |
          ARP Reply (unicast → Alpine's MAC)
          "192.168.200.20 is at dd:ee:ff:44:55:66"
```

**Why it matters for SOC:** ARP has no authentication mechanism — any device can send an unsolicited ARP Reply (called a **Gratuitous ARP**) claiming to be any IP. This is the foundation of ARP spoofing attacks, where an attacker poisons the ARP cache of victims to intercept traffic (Man-in-the-Middle).

Normal ARP behavior to establish as baseline:

- One Request followed by exactly one Reply
- Request destination is always `ff:ff:ff:ff:ff:ff` (broadcast)
- Reply is always unicast back to the requester
- ARP packets are small — 28 bytes payload, 42 bytes total frame

#### Capture in This Project

**Lab addresses:**

```
Alpine Linux  : 192.168.200.10
Windows 10    : 192.168.200.20
PnetLab VM    : 192.168.122.217  (capture bridge)
```

**Step 1 — Flush the ARP cache on Alpine first**

This is important: if Alpine already has Windows' MAC in its cache, no ARP Request will be sent.

```bash
# On Alpine
ip neigh flush all

# Verify the cache is empty
ip neigh show
```

![[Step-1-Flush-arp-cache.png]]

**Step 2 — Start the capture pipeline on the Arch host**

```bash
ssh root@192.168.122.217 \
  "tcpdump -i pnet1 arp -U -s0 -w -" | \
  tee ~/Packet-Analysis-Lab/captures/baseline/phase3_arp.pcap | \
  wireshark -k -i -
```

**Step 3 — Generate ARP traffic from Alpine**

```bash
# On Alpine — ping triggers an ARP Request if MAC is not cached
ping -c 4 192.168.200.20
```

![[Arp-Alpine-win.png]]

**Wireshark filter:** `arp`

**Key fields to observe in Wireshark:**

|Field|Expected Value|Significance|
|---|---|---|
|Opcode|1 (Request) / 2 (Reply)|Identifies packet direction|
|Sender MAC|Alpine's MAC|Who is asking|
|Sender IP|192.168.200.10|Who is asking|
|Target IP|192.168.200.20|Who is being asked|
|Target MAC (Request)|`00:00:00:00:00:00`|Unknown — that's why we're asking|
|Destination Ethernet (Request)|`ff:ff:ff:ff:ff:ff`|Broadcast|
|Destination Ethernet (Reply)|Alpine's MAC|Unicast reply|

![[Arp-frame.png]]

**Verify the ARP cache was updated:**

```bash
# On Alpine after the ping
ip neigh show
# Expected: 192.168.200.20 dev eth0 lladdr dd:ee:ff:xx:xx:xx REACHABLE

# On Windows
arp -a
# Expected: 192.168.200.10 → Alpine's MAC
```

![[Arp-cache-updated.png]]
 _Figure — ARP cache Alpine 

![[arp-cache-win.png]]
_Figure — ARP windows 10_
 

![[arp_request.png.png]]
 _Figure — ARP Request broadcast from Alpine to the network_

![[arp_reply.png]]
 _Figure — ARP Reply unicast from Windows back to Switch

---

### 2. ICMP — Internet Control Message Protocol

#### Concept

ICMP is a diagnostic protocol that operates at Layer 3. Unlike TCP or UDP, it is not used to transfer application data — its purpose is to report network conditions and test reachability. The most common use is the **ping** command, which sends ICMP Echo Request packets and expects Echo Reply packets in return.

Every ICMP message has a **type** and a **code** that define its purpose:

```
Common ICMP Types:
  Type 0  — Echo Reply       (response to a ping)
  Type 3  — Destination Unreachable
  Type 8  — Echo Request     (the ping itself)
  Type 11 — Time Exceeded    (TTL expired — used by traceroute)
```

The **TTL (Time To Live)** field in the IP header decrements by 1 at each router hop. When it reaches 0, the router discards the packet and sends back an ICMP Type 11 (Time Exceeded) to the sender. This is the mechanism traceroute exploits to map network paths.

```
[Alpine]                              [Windows]
   |                                      |
   |── ICMP Echo Request (type 8) ───────►|
   |   seq=1, ttl=64, id=1234             |
   |                                      |
   |◄── ICMP Echo Reply (type 0) ─────── |
   |    seq=1, ttl=128                    |
   |                                      |
   |── ICMP Echo Request (type 8) ───────►|
   |   seq=2                              |
   |◄── ICMP Echo Reply (type 0) ─────── |
       seq=2
```

**Why it matters for SOC:** ICMP is often overlooked because it seems harmless, but it is commonly abused:

- **ICMP flood (ping flood):** sending massive volumes of Echo Requests to exhaust a target's resources
- **ICMP tunneling:** encapsulating arbitrary data inside ICMP payloads to exfiltrate data or establish covert C2 channels
- **Ping sweep:** sending Echo Requests to every IP in a range to discover live hosts — a classic recon technique

Normal ICMP behavior: one Request per Reply, regular timing intervals, payload size consistent (typically 56 bytes of data), TTL values consistent with the OS (Linux default: 64, Windows default: 128).

#### Capture in This Project

> **Lab note — Capture interface:** During Phase 3, traffic between Alpine and
> Windows was found not to traverse `pnet1` as expected. Investigation with
> `tcpdump -i any` and `brctl show` revealed the actual bridge topology:
> `pnet1` connects the IOU L2 switch to the external network (eth1), while
> internal VM-to-VM traffic flows through `vnet1_2` (Alpine ↔ Switch) and
> `vnet1_3` (Windows ↔ Switch). All captures involving traffic between lab
> endpoints therefore use `vnet1_2` instead of `pnet1`. Protocols that reach
> external destinations (DNS to 8.8.8.8, Traceroute to 8.8.8.8) continue to
> use `pnet1` as that traffic exits through the external interface.

**Step 1 — Start the capture pipeline**

```bash
ssh root@192.168.122.217 "tcpdump -i vnet1_2 icmp -U -s0 -w -" | \ tee ~/Packet-Analysis-Lab/captures/baseline/phase3_icmp.pcap | \ wireshark -k -i -
```

**Step 2 — Generate ICMP traffic from Alpine**

```bash
# On Alpine
ping -c 10 192.168.200.20
```

![[ICMP-Ping-alpine-wind.png]]

**Wireshark filter:** `icmp`

**Key fields to observe:**

|Field|Expected Value|Significance|
|---|---|---|
|Type|8 (Request) / 0 (Reply)|Direction of the message|
|Code|0|Normal — non-zero codes indicate errors|
|Sequence number|Increments: 1, 2, 3...|Matches Request to Reply|
|Identifier|Same in Request and Reply|Links a ping session|
|TTL (IP header)|64 from Alpine, 128 from Windows|OS fingerprinting|
|Payload size|56 bytes (Linux default)|Deviations may indicate tunneling|

![[phase3_icmp_request.png]]
 _Figure — ICMP Echo Request from Alpine showing type, sequence number, and TTL_

![[phase3_icmp_reply.png]]
_Figure — ICMP Echo Reply from Windows with TTL=128_

---

### 3. DNS — Domain Name System

#### Concept

DNS is the internet's phonebook. Humans use domain names like `google.com`; computers communicate using IP addresses like `142.250.185.46`. DNS translates between the two.

When a device needs to resolve a domain name, it sends a **DNS Query** to a DNS server (in this lab: Google's public resolver at `8.8.8.8`). The server responds with a **DNS Response** containing the answer. This exchange typically happens over **UDP port 53** because it is fast and DNS messages are usually small. For large responses (such as zone transfers), DNS switches to **TCP port 53**.

```
[Alpine]                        [8.8.8.8 - Google DNS]
   |                                      |
   |── DNS Query (UDP/53) ───────────────►|
   |   "What is the IP of google.com?"    |
   |   Type: A (IPv4)                     |
   |                                      |
   |◄── DNS Response ─────────────────── |
       "google.com → 142.250.185.46"
       TTL: 300 seconds
```

A DNS packet contains several key sections:

- **Questions:** what is being asked (domain name + record type)
- **Answers:** the resolved records
- **Transaction ID:** a random number that links the query to its response
- **Flags:** indicate whether it is a query or response, and the response code (NOERROR, NXDOMAIN...)

Common DNS record types:

|Type|Purpose|Example|
|---|---|---|
|A|IPv4 address|`google.com → 142.250.x.x`|
|AAAA|IPv6 address|`google.com → 2607:f8b0:...`|
|MX|Mail server|`gmail.com → smtp.google.com`|
|TXT|Text records|SPF, DKIM, verification tokens|
|CNAME|Alias|`www.example.com → example.com`|

**Why it matters for SOC:** DNS is one of the most commonly abused protocols because it is almost always allowed through firewalls:

- **DNS exfiltration:** encoding stolen data inside DNS query subdomains (e.g., `c2VjcmV0ZGF0YQ.evil.com`) to bypass data loss controls
- **DNS C2 beaconing:** malware using DNS queries to communicate with command-and-control servers
- **DNS spoofing:** returning false answers to redirect users to malicious sites

Red flags: queries to unusual or newly registered domains, unusually long subdomain labels, high-frequency queries to a single domain, TXT record responses with encoded data, queries to non-standard DNS servers.

#### Capture in This Project

**Step 1 — Install DNS tools on Alpine if not present**

```bash
apk add bind-tools
```

**Step 2 — Start the capture pipeline**

```bash
ssh root@192.168.122.217 \
  "tcpdump -i pnet1 port 53 -U -s0 -w -" | \
  tee ~/Packet-Analysis-Lab/captures/baseline/phase3_dns.pcap | \
  wireshark -k -i -
```

**Step 3 — Generate DNS traffic from Alpine**

```bash
# Standard A record lookup
nslookup google.com 8.8.8.8

# Query both A and AAAA records
dig github.com

# Explicit server + domain
dig @8.8.8.8 tryhackme.com

# MX record query
dig @8.8.8.8 MX gmail.com
```

![[DNS-Querys.png]]

**Wireshark filter:** `dns`

**Key fields to observe:**

|Field|Expected Value|Significance|
|---|---|---|
|Transaction ID|Same in query and response|Links query to its answer|
|Flags|QR bit: 0=query, 1=response|Direction|
|Questions|Domain + record type|What was asked|
|Answer RRs|Resolved IP + TTL|The result|
|Transport|UDP/53 (standard)|TCP/53 only for large responses|
|Response code|NOERROR (0)|NXDOMAIN means domain doesn't exist|
![[DNS-Alpine-google.png]]
_Figure — DNS Query from Alpine for google.com, showing Transaction ID and question section_
![[DNS Response from 8.8.8.8 with A and AAAA records and TTL values.png]]
 _Figure — DNS Response from 8.8.8.8 with A and AAAA records and TTL values_

---

### 4. DHCP — Dynamic Host Configuration Protocol

#### Concept

When a device joins a network, it needs an IP address, a subnet mask, a default gateway, and DNS server addresses. DHCP automates this process — instead of manually configuring each device, a DHCP server assigns these values dynamically.

The process follows a four-step sequence known as **DORA**:

```
[Alpine - no IP yet]              [DHCP Server]
        |                               |
        |── DHCP Discover ─────────────►|
        |   Broadcast: "I need an IP"   |
        |   src: 0.0.0.0               |
        |   dst: 255.255.255.255        |
        |                               |
        |◄── DHCP Offer ────────────── |
        |    "I offer you 192.168.200.10"|
        |    + mask, gateway, DNS, lease |
        |                               |
        |── DHCP Request ──────────────►|
        |   "I accept 192.168.200.10"   |
        |   (still broadcast)           |
        |                               |
        |◄── DHCP Acknowledge ───────── |
            "Confirmed. Lease: 24h"
```

Key details: the initial Discover and Request are sent as broadcasts because the client has no IP yet. The server and client are identified using a **Transaction ID** (a random number chosen by the client) and the client's **MAC address**.

**Why it matters for SOC:**

- **Rogue DHCP server:** an attacker sets up their own DHCP server on the network and responds to Discover messages faster than the legitimate server. Clients that accept the rogue offer receive attacker-controlled gateway and DNS addresses — enabling MITM and DNS hijacking at scale.
- **DHCP starvation:** an attacker sends thousands of Discover messages with spoofed MAC addresses, exhausting the DHCP pool. Legitimate clients can no longer obtain IPs. This is a denial-of-service attack.

#### Capture in This Project

**Server-side setup — Windows 10**

DHCP is typically served by the network infrastructure. In this lab, Alpine uses a static IP, so DHCP traffic is generated by forcing Alpine to release and request an IP via `udhcpc`.

> **Note:** If Windows 10 is to act as the DHCP server for this exercise, enable Internet Connection Sharing (ICS) or install a DHCP server role. In this lab, the router/PnetLab environment provides DHCP.

**Step 1 — Start the capture pipeline**

```bash
ssh root@192.168.122.217 \
  "tcpdump -i vnet1_2 'port 67 or port 68' -U -s0 -w -" | \
  tee ~/Packet-Analysis-Lab/captures/baseline/phase3_dhcp.pcap | \
  wireshark -k -i -
```

**Step 2 — Force a DHCP renewal on Alpine**

```bash
# Option A — bring the interface down and up (triggers full DORA)
ip link set eth0 down && ip link set eth0 up

# Option B — use udhcpc to request a new lease
udhcpc -i eth0
```

![[Force a DHCP renewal on Alpine.png]]
 
**Wireshark filter:** `dhcp`

**Key fields to observe:**

| Field            | Expected Value                        | Significance                      |
| ---------------- | ------------------------------------- | --------------------------------- |
| Message type     | 1=Discover, 2=Offer, 3=Request, 5=ACK | DORA step                         |
| Transaction ID   | Same across all 4 packets             | Links the full exchange           |
| Client MAC       | Alpine's MAC                          | Identifies the requesting device  |
| Your IP (yiaddr) | 192.168.200.x (in Offer/ACK)          | The address being assigned        |
| Option 51        | Lease time in seconds                 | How long the IP is valid          |
| Option 3         | Default gateway                       | Router address provided by server |
| Option 6         | DNS server(s)                         | DNS provided by server            |

 ![[DHCP Discover broadcast from Alpine with src 0.0.0.0 and dst 255.255.255.255.png]]
 _Figure — DHCP Discover broadcast from Alpine with src 0.0.0.0 and dst 255.255.255.255_

![[DORA.png]]
_Figure — Full DORA sequence visible in Wireshark, four packets linked by Transaction ID_

---

### 5. HTTP — Hypertext Transfer Protocol

#### Concept

HTTP is the protocol that powers the web. It is a **request-response** protocol: a client (browser, curl, wget) sends an HTTP Request to a server, and the server responds with an HTTP Response. Everything in HTTP is **plaintext** — headers, body, and crucially, any credentials — which is why HTTPS (HTTP over TLS) was developed.

An HTTP session always begins with a TCP three-way handshake before any HTTP data is exchanged:

```
[Alpine - client]                    [Web Server]
        |                                  |
        |── SYN ──────────────────────────►|    TCP handshake
        |◄── SYN-ACK ─────────────────── |
        |── ACK ──────────────────────────►|
        |                                  |
        |── HTTP GET / HTTP/1.1 ──────────►|    HTTP Request
        |   Host: neverssl.com             |
        |   User-Agent: curl/8.x           |
        |                                  |
        |◄── HTTP/1.1 200 OK ──────────── |    HTTP Response
        |    Content-Type: text/html        |
        |    [page content in plaintext]    |
        |                                  |
        |── FIN ──────────────────────────►|    TCP teardown
        |◄── FIN-ACK ─────────────────── |
```

Common HTTP methods:

|Method|Purpose|SOC Note|
|---|---|---|
|GET|Request a resource|Standard browsing|
|POST|Submit data to server|Login forms, file uploads — credentials visible|
|PUT|Upload/replace a resource|Potential data exfiltration|
|HEAD|Request headers only|Recon — checking if a server is alive|

HTTP status codes indicate the server's response:

- `200 OK` — success
- `301/302` — redirect (common for HTTP → HTTPS)
- `401` — authentication required
- `403` — forbidden
- `404` — not found
- `500` — server error

**Why it matters for SOC:** HTTP traffic is completely readable on the wire. Any credentials submitted via HTTP login forms, Basic Authentication headers, or POST bodies are visible to anyone with network access. This is why capturing HTTP traffic in a lab environment is a clear demonstration of why plaintext protocols are dangerous.

#### Capture in This Project

**Step 1 — Install curl on Alpine if not present**

```bash
apk add curl
```

**Step 2 — Start the capture pipeline**

```bash
ssh root@192.168.122.217 \
  "tcpdump -i pnet1 port 80 -U -s0 -w -" | \
  tee ~/Packet-Analysis-Lab/captures/baseline/phase3_http.pcap | \
  wireshark -k -i -
```

**Step 3 — Generate plain HTTP traffic from Alpine**

These sites intentionally serve HTTP without redirecting to HTTPS:

```bash
# Plain HTTP — no redirect to HTTPS
curl -v http://neverssl.com

# Another reliable plain HTTP site
curl -v http://httpforever.com
```

![[Https.png]]

> **Note:** Most modern sites redirect HTTP to HTTPS (301 redirect). Use `neverssl.com` or `httpforever.com` to capture readable HTTP content without TLS.

**Wireshark filter:** `ip.src == 192.168.200.10 or ip.dst == 192.168.200.10`

To follow the full TCP + HTTP session: right-click any HTTP packet → _Follow → TCP Stream_. This reconstructs the full exchange as readable text.

![[Tcp-follow-stream.png]]

**Key fields to observe:**

|Field|Expected Value|Significance|
|---|---|---|
|Request Method|GET|Standard page request|
|Request URI|`/` or specific path|What was requested|
|Host header|`neverssl.com`|Target domain|
|User-Agent|`curl/8.x`|Client identification — forgeable|
|Response Code|200 OK|Successful response|
|Content-Type|`text/html`|Type of content returned|
|Authorization header|If present: credentials in plaintext|Critical finding|

![[HTTP GET request from Alpine showing headers in plaintext.png]]
 _Figure — HTTP GET request from Alpine showing headers in plaintext_

![[HTTP 200 OK response with plaintext body visible.png]]
 _Figure — HTTP 200 OK response with plaintext body visible_

---

### 6. FTP — File Transfer Protocol

#### Concept

FTP is one of the oldest protocols still in use. Its purpose is to transfer files between a client and a server. Like HTTP, FTP transmits everything in **plaintext** — including the username and password used to authenticate.

FTP uses **two separate connections**:

```
[Alpine - FTP client]              [Windows - FTP server]
        |                                   |
        |── TCP SYN ────────────────────────►|   Control channel
        |   port 21 (control)               |   established first
        |◄── SYN-ACK ──────────────────── |
        |── ACK ─────────────────────────── |
        |                                   |
        |◄── 220 FTP server ready ───────── |   Server banner
        |── USER alpine ───────────────────►|   Username in plaintext
        |◄── 331 Password required ──────── |
        |── PASS secret123 ────────────────►|   Password in plaintext
        |◄── 230 Login successful ───────── |
        |                                   |
        |── LIST ────────────────────────── |   List directory
        |◄── (data connection on port 20) ─ |   Data channel opened
        |◄── 226 Transfer complete ──────── |
```

The **control channel** (port 21) carries all commands and responses. The **data channel** (port 20 in active mode, or a negotiated port in passive mode) carries the actual file content.

**Why it matters for SOC:** FTP is a textbook example of an insecure legacy protocol. In a packet capture, the username and password are visible in plain text — no decryption required. SFTP (SSH File Transfer Protocol) and FTPS (FTP over TLS) exist as secure alternatives but FTP servers are still commonly found in enterprise environments.

#### Capture in This Project

**Server-side setup — Windows 10 (IIS FTP)**

FileZilla Server could not be installed as the Windows 10 VM had no internet access inside PnetLab. IIS FTP was used instead — it is built into Windows 10 and requires no download.:

```
1. Control Panel → Programs → Turn Windows features on/off 
2. Enable: Internet Information Services → FTP Server → FTP Service
3. Enable: Web Management Tools → IIS Management Console 
4. Open IIS Manager (Win+R → inetmgr)
5. Right-click server name → Add FTP Site
6. Site name: lab-ftp | Physical path: C:\Users\Public 
7. IP: All Unassigned | Port: 21 | No SSL 
8. Authentication: Anonymous | Allow: All Users | Permissions: Read + Write 
9. Verify: netstat -an | findstr :21
```

![[Win-10-ftp-activation.png]]

![[win-ftp-done.png]]

![[ftp-lisneting.png]]

**Lab note — Windows Firewall:** The Windows Firewall blocked the FTP active mode data channel, preventing Alpine from listing directory contents. The firewall was disabled for the duration of this capture: `netsh advfirewall set allprofiles state off`

**Step 1 — Install FTP client on Alpine**

```bash
apk add lftp
```

**Step 2 — Start the capture pipeline**

```bash
ssh root@192.168.122.217 \
  "tcpdump -i vnet1_2 port 21 or port 20 -U -s0 -w -" | \
  tee ~/Packet-Analysis-Lab/captures/baseline/phase3_ftp.pcap | \
  wireshark -k -i -
```

**Step 3 — Connect to the FTP server from Alpine**

```bash
# Using lftp (more verbose output than ftp)
lftp -u anonymous,anonymous 192.168.200.20

# Once connected, run some commands to generate traffic
lftp labuser@192.168.200.20:~> ls
lftp labuser@192.168.200.20:~> bye
```

![[ftp-connected.png]]

**Wireshark filter:** `ftp`

To read the credentials directly: right-click any FTP packet → _Follow → TCP Stream_. The `USER` and `PASS` commands are visible in clear text.

**Key fields to observe:**

| Field              | Expected Value   | Significance                  |
| ------------------ | ---------------- | ----------------------------- |
| Response code 220  | Server banner    | Server identification         |
| USER command       | `labuser`        | Username in plaintext         |
| PASS command       | `labpass`        | Password in plaintext         |
| Response 230       | Login successful | Confirms valid credentials    |
| LIST / RETR / STOR | FTP commands     | Actions performed after login |
| Port 20 traffic    | File content     | Data channel, also plaintext  |

![[FTP control channel showing USER and PASS in plaintext.png]]
  _Figure — FTP control channel showing USER and PASS in plaintext_


---

### 7. SSH — Secure Shell

#### Concept

SSH is the encrypted alternative to protocols like Telnet and FTP. It provides a secure channel over an unsecured network, and is the standard method for remote administration of Linux servers. Unlike FTP or HTTP, **everything after the initial handshake is encrypted** — an attacker with access to the network capture cannot read the commands or responses.

The SSH connection process has several distinct phases:

```
[Arch Host - SSH client]           [Alpine - SSH server]
        |                                  |
        |── TCP handshake ────────────────►|
        |◄──────────────────────────────── |
        |                                  |
        |◄── SSH banner ─────────────────  |   "SSH-2.0-OpenSSH_9.x"
        |── Client banner ────────────────►|   Version negotiation (visible)
        |                                  |
        |◄──► Key exchange (DH) ──────────►|   Diffie-Hellman — establishes
        |     Algorithm negotiation         |   shared secret without
        |     Host key verification         |   transmitting it
        |                                  |
        |── User authentication ───────────►|   Encrypted from this point
        |◄── Auth success ──────────────── |
        |                                  |
        |◄──► Encrypted session ──────────►|   All commands/responses
              [payload unreadable]              encrypted
```

**What is visible in a capture:**

- The SSH version strings (banner exchange) — `SSH-2.0-OpenSSH_9.x`
- The key exchange algorithm negotiation
- The size and timing of packets — which can reveal session activity patterns

**What is NOT visible:**

- Credentials (username, password, or key)
- Commands executed
- Any output

**Diffie-Hellman key exchange** (simplified): both sides agree on a shared secret without ever transmitting it — each sends a public value, and through mathematical operations, both independently compute the same shared key. An observer seeing both public values cannot compute the secret.

**Why it matters for SOC:** SSH itself is secure by design, but it is frequently targeted by brute-force attacks — automated tools that try thousands of username/password combinations against port 22. The signature in a packet capture is a large number of TCP connections to port 22 that end quickly with RST (connection reset after failed authentication).

#### Capture in This Project

**Server-side setup — Alpine**

```bash
# Install and start OpenSSH on Alpine
apk add openssh
rc-service sshd start

# Enable sshd at boot
rc-update add sshd

# Verify it is listening
netstat -tlnp | grep :22
```

**Step 1 — Start the capture pipeline**

```bash
ssh root@192.168.122.217 \
  "tcpdump -i vnet1_2 port 22 -U -s0 -w -" | \
  tee ~/Packet-Analysis-Lab/captures/baseline/phase3_ssh.pcap | \
  wireshark -k -i -
```

**Step 2 — Initiate an SSH connection from the Arch host**

```bash
# From Arch host — connect to Alpine
ssh labuser@192.168.200.10

# Run a few commands to generate encrypted session traffic
whoami
uname -a
ls -la
exit
```
![[SSH.png]]

**Wireshark filter:** `ssh` or `tcp.port == 22`

**Key fields to observe:**

|Field|Expected Value|Significance|
|---|---|---|
|SSH banner|`SSH-2.0-OpenSSH_9.x`|Version — visible before encryption|
|Key Exchange Init|Algorithm list|Cipher negotiation — visible|
|Encrypted packets|Payload: `[encrypted]`|All session data — unreadable|
|Packet size pattern|Many small fixed-size packets|Pattern of interactive typing|
|New Keys message|Marks transition|Point where encryption begins|

 ![[SSH-Banner.png]]
 _Figure — SSH version banner exchange visible before encryption begins_

![[encrypted-packet.png]]
 _Figure — SSH session packets showing encrypted payload — content unreadable_

---

### 8. Traceroute — ICMP TTL Path Discovery

#### Concept

Traceroute is a diagnostic tool that maps the path packets take from a source to a destination, showing every router (hop) along the way. It exploits the **TTL (Time To Live)** field in the IP header.

Every IP packet has a TTL value that decrements by 1 at each router. When TTL reaches 0, the router discards the packet and sends back an **ICMP Type 11 — Time Exceeded** message to the original sender. Traceroute deliberately starts with TTL=1 and increases it by 1 for each probe:

```
[Alpine]                  [Router 1]      [Router 2]        [8.8.8.8]
   |                          |               |                  |
   |── probe TTL=1 ──────────►|               |                  |
   |   (packet dies here)     |               |                  |
   |◄── ICMP Type 11 ──────── |               |                  |
   |   "TTL exceeded"         |               |                  |
   |   from Router 1's IP     |               |                  |
   |                          |               |                  |
   |── probe TTL=2 ──────────►──────────────►|                  |
   |   (packet dies here)                     |                  |
   |◄── ICMP Type 11 ─────────────────────── |                  |
   |   from Router 2's IP                     |                  |
   |                                          |                  |
   |── probe TTL=3 ──────────►──────────────►──────────────────►|
   |                                                             |
   |◄── ICMP Echo Reply (type 0) ─────────────────────────────── |
       Destination reached
```

By collecting the source IP of each ICMP Type 11 response, traceroute builds a map of the network path. By default, Alpine's `traceroute` uses UDP probes; `traceroute -I` uses ICMP. Windows uses ICMP (`tracert`) by default.

**Why it matters for SOC:** Traceroute is a standard network diagnostic tool, but it is also a reconnaissance technique. An attacker running traceroute against internal infrastructure reveals the internal network topology — router IPs, network segments, hop counts. In a monitored environment, sequential ICMP Type 11 responses from multiple hops to a single source is a recognizable pattern.

#### Capture in This Project

**Step 1 — Start the capture pipeline**

```bash
ssh root@192.168.122.217 \
  "tcpdump -i pnet1 icmp -U -s0 -w -" | \
  tee ~/Packet-Analysis-Lab/captures/baseline/phase3_traceroute.pcap | \
  wireshark -k -i -
```

**Step 2 — Run traceroute from Alpine**

```bash
# Install traceroute if not present
apk add traceroute

# ICMP-based traceroute (easier to observe in Wireshark)
traceroute -I 8.8.8.8

# Standard UDP-based traceroute
traceroute 8.8.8.8
```
![[Traceroute.png]]

**Wireshark filter:** `icmp.type == 11`

This filter shows only the ICMP Time Exceeded responses — the replies from each hop along the path.

To see the full picture (probes + replies): `icmp`

**Key fields to observe:**

|Field|Expected Value|Significance|
|---|---|---|
|ICMP Type|11 (Time Exceeded)|The TTL-expired reply from each hop|
|Source IP (reply)|Router's IP at that hop|Reveals network topology|
|TTL in original packet|Starts at 1, increments|Traceroute probe sequence|
|Inner IP header|Preserved — shows original dest|Included in ICMP error messages|
|Number of hops|Typically 5–15 to internet|Hop count to destination|
![[time-to-live-exeded.png]]
_Figure — ICMP Type 11 Time_

---

## C) Wireshark — SOC Reference Table

| Protocol   | Wireshark Filter | Normal Pattern                                   | SOC Red Flag                                                                        |
| ---------- | ---------------- | ------------------------------------------------ | ----------------------------------------------------------------------------------- |
| ARP        | `arp`            | 1 Request → 1 Reply, unicast reply               | Broadcast storm, repeated Gratuitous ARP, MAC/IP mismatch                           |
| ICMP       | `icmp`           | 1 Echo Request → 1 Echo Reply, regular intervals | Flood (100s/sec), large payload (>100 bytes), ICMP tunneling                        |
| DNS        | `dns`            | Query → fast response, UDP/53                    | Unknown resolver IP, base64-encoded subdomains, long TXT records, high frequency    |
| DHCP       | `dhcp`           | DORA sequence, one exchange per client           | Multiple Discovers without ACK (starvation), Offer from unknown server (rogue DHCP) |
| HTTP       | `http`           | GET/POST → 200 OK, standard headers              | Credentials in Authorization header, sensitive data in POST body                    |
| FTP        | `ftp`            | USER/PASS → 230, standard commands               | Credentials visible in stream (always), connections from unexpected hosts           |
| SSH        | `tcp.port==22`   | Banner + encrypted session                       | Multiple rapid TCP RST on port 22 (brute force pattern)                             |
| Traceroute | `icmp.type==11`  | Sequential TTL Exceeded, one per hop             | Systematic sweep of destination IPs, traceroute from unexpected internal host       |
