<div align="center">

# geocheck

**Where the internet thinks you are – and how directly you actually reach it.**

[![CI](https://img.shields.io/github/actions/workflow/status/remnawave/geocheck/ci.yml?branch=main&style=for-the-badge&logo=githubactions&logoColor=white&label=CI)](https://github.com/remnawave/geocheck/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/remnawave/geocheck?style=for-the-badge&logo=github&logoColor=white&color=7b3fe4)](https://github.com/remnawave/geocheck/releases/latest)
[![Docker pulls](https://img.shields.io/docker/pulls/remnawave/geocheck?style=for-the-badge&logo=docker&logoColor=white&color=2496ed)](https://hub.docker.com/r/remnawave/geocheck)
[![Image size](https://img.shields.io/docker/image-size/remnawave/geocheck/ing?style=for-the-badge&logo=docker&logoColor=white&color=2496ed&label=image)](https://hub.docker.com/r/remnawave/geocheck/tags)
[![Go](https://img.shields.io/github/go-mod/go-version/remnawave/geocheck?style=for-the-badge&logo=go&logoColor=white&color=00add8)](go.mod)
[![License](https://img.shields.io/github/license/remnawave/geocheck?style=for-the-badge&color=5ee08a)](LICENSE)

```sh
curl -fsSL https://geocheck.ing | sh
```

<img src="https://raw.githubusercontent.com/remnawave/geocheck/main/docs/img/demo.gif" alt="geocheck producing a full report: address reputation, geolocation consensus, connectivity checks, path analysis and service availability" width="920">

<sub>Recorded from <code>geocheck --demo</code>, which renders invented measurements in reserved
documentation address space – so this animation publishes nobody's real address or route.</sub>

</div>

---

Every IP geolocation tool answers _where does the internet think I am_. That is
half the question. The other half is **how your packets actually get there** –
whether you enter Google's network on-net or three transit carriers later,
whether a tunnel is quietly adding 90 ms, whether something is answering on a
destination's behalf.

geocheck answers both, in one pass, and prints the evidence.

## Quick start

The launcher needs nothing installed and leaves nothing behind. It uses docker,
else podman, else it downloads the release binary for your platform and verifies
its checksum – then removes whatever it pulled or downloaded when the run ends.
An image you already had is left untouched.

```sh
curl -fsSL https://geocheck.ing | sh

# Flags go after -s --
curl -fsSL https://geocheck.ing | sh -s -- -4 --detail
```

To pin the runtime instead of letting it choose, name one. It is then a
requirement rather than a preference: if it is missing the launcher says so
instead of quietly falling through to the next one.

```sh
curl -fsSL https://geocheck.ing | sh -s -- --runtime binary   # never a container
curl -fsSL https://geocheck.ing | sh -s -- --runtime docker
curl -fsSL https://geocheck.ing | sh -s -- --runtime podman

# Or as an environment variable, which composes better with a wrapper script
curl -fsSL https://geocheck.ing | GEOCHECK_RUNTIME=binary sh
```

Launcher options must come first and are not passed on; everything after them
goes to geocheck. `sh -s -- --launcher-help` lists them.

Prefer to see the command you are running? Straight from Docker Hub:

```sh
docker pull remnawave/geocheck:ing
docker run --rm -it --network host remnawave/geocheck:ing
```

Or as a binary, with no container at all:

```sh
go install github.com/remnawave/geocheck/cmd/geocheck@latest
```

## What it measures

|     |                           |                                                                                                                                                                                                              |
| --- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 🛰️  | **Address reputation**    | Datacenter or residential, known VPN or proxy, and a risk score. Usually the thing that explains a refusal the geolocation table cannot.                                                                     |
| 🌍  | **Geolocation consensus** | Asks ~40 GeoIP APIs and consumer services which country they serve you, and shows exactly where they disagree.                                                                                               |
| 📶  | **Connectivity checks**   | Runs the endpoints operating systems use to decide they are online – Google's `generate_204`, Apple's hotspot-detect, Microsoft's NCSI – and compares each answer against the response its vendor specifies. |
| 🧭  | **Path analysis**         | Traces the route to the major networks, annotates every hop with its autonomous system, and judges how directly each one is reached.                                                                         |
| 🎬  | **Service availability**  | Asks Netflix, ChatGPT, YouTube Premium, Claude and TikTok whether they will actually serve you.                                                                                                              |

It also checks whether the measurement itself is being tampered with – a tunnel
carrying your default route, a resolver answering on someone else's behalf –
because those invalidate everything above them.

## The part other tools skip

<div align="center">
<img src="https://raw.githubusercontent.com/remnawave/geocheck/main/docs/img/connectivity.gif" alt="the direct-connectivity table: per-target verdict, RTT, loss, hop count and the autonomous system the path ends in" width="920">
</div>

Latency alone cannot tell you whether a connection is direct – a well-peered DSL
line idles higher than a badly-routed fibre one. So every verdict is measured
**relative to the floor**: the fastest round trip this connection achieved to
anything at all. That floor is the cost of your access network, which no amount
of good peering gets below. What the excess above it buys you is information.

| Verdict           | What it means                                                                                                                  |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `direct / on-net` | The destination network is entered without crossing a transit provider, at the best latency this connection achieves anywhere. |
| `regional`        | Entered without transit, but from further away – a regional exchange rather than an on-net cache.                              |
| `transit`         | One or more transit carriers sit between you and the destination network.                                                      |
| `detour`          | The traffic travels far further than the destination warrants – typically a tunnel exiting in another region.                  |
| `intercepted`     | Something answered on the destination's behalf, far closer than the destination can possibly be.                               |
| `unreachable`     | Nothing answered at all.                                                                                                       |

All five of Telegram's data centres are measured by default. Which one serves
you is fixed by where the account was registered, not by where you are, so a
European user can legitimately be pinned to a US one – this shows what each
would cost.

## Usage

```sh
# Everything, both address families
docker run --rm -it --network host remnawave/geocheck:ing

# IPv4 only, with every hop of every path
docker run --rm -it --network host remnawave/geocheck:ing -4 -d

# Machine-readable
docker run --rm --network host remnawave/geocheck:ing --json > report.json

# Just "is my connection direct" – skip the geolocation half
docker run --rm -it --network host remnawave/geocheck:ing --no-geo

# Trace every target in the catalogue
docker run --rm -it --network host remnawave/geocheck:ing -T all -d

# See a sample report without measuring anything
docker run --rm -it remnawave/geocheck:ing --demo
```

Use `-it` so colours and the progress line render; drop it when piping.

<details>
<summary><b>Why <code>--network host</code> is in every example</b></summary>

<br>

Without it the container gets its own network namespace, so the trace starts at
Docker's bridge instead of your real gateway, and the exit address is whatever
the host happens to SNAT to rather than one you can choose. On Linux it makes
the measurement describe the host; on macOS and Windows the "host" is a Linux
VM, so it shares that VM's namespace instead and buys you less.

</details>

<details>
<summary><b>Under podman, add <code>--cap-add=NET_RAW</code></b></summary>

<br>

Docker grants that capability by default and podman does not. Without it
geocheck cannot open the raw socket the path trace needs – it still runs, but
reports latency only, with no hops.

```sh
podman run --rm -it --network host --cap-add=NET_RAW remnawave/geocheck:ing
```

The `geocheck.ing` launcher passes it for you.

</details>

<details>
<summary><b>Choosing which address is measured</b></summary>

<br>

On a host with several addresses, the one geocheck reports is whichever the
kernel picks by default. To measure a specific one, name it:

```sh
docker run --rm -it --network host remnawave/geocheck:ing -i 203.0.113.10
```

`-i` accepts an interface name **or** any address assigned to the host, so you
can compare what two uplinks, two tunnels, or two of a server's many addresses
actually see. It pins the source of every socket – HTTP checks, DNS and ICMP
probes alike. This needs `--network host`: without it the container cannot see
the host's addresses at all.

</details>

<details>
<summary><b>Running the binary, and the raw-socket privilege</b></summary>

<br>

```sh
go install github.com/remnawave/geocheck/cmd/geocheck@latest
```

Or download one from the [releases page](https://github.com/remnawave/geocheck/releases).

Hop-by-hop tracing needs a raw ICMP socket. The container image already carries
the capability, so `docker run` needs nothing beyond the flags above. For a
plain binary, grant it once:

```sh
sudo setcap cap_net_raw+p ./geocheck     # Linux
sudo ./geocheck                          # macOS
```

**Without the privilege it still works** – it measures destination latency over
a TCP handshake instead of walking the path, and says so in the output.

</details>

## Options

```
geocheck [options]

  -4, --ipv4              test IPv4 only
  -6, --ipv6              test IPv6 only
  -i, --interface IF|IP   bind all traffic to an interface name or a local source address
  -p, --proxy HOST:PORT   route checks through a SOCKS5 proxy
      --doh MODE          DoH resolver: auto (default), off, or an https:// URL
  -t, --timeout SEC       per-request timeout (default 8)
  -g, --group GROUP       geo groups to run: all, services, geoip, cdn
  -T, --targets SET       trace targets: a tag, an id, 'all', or a comma-separated list
      --portal SET        connectivity-check set: a tag, an id, or 'all'
  -d, --detail            print the full per-hop table for every target
      --rounds N          probes per hop (default 5)
      --max-ttl N         maximum TTL (default 30)
      --no-geo            skip geolocation checks
      --no-mtr            skip connectivity checks
      --no-detect         skip tunnel and DNS interception checks
      --no-portal         skip the captive-portal connectivity checks
      --no-access         skip the service-availability checks
      --no-reputation     skip the address reputation lookup
      --proxycheck-key K  proxycheck.io API key ($PROXYCHECK_API_KEY)
      --mask              mask the public address in the output
  -j, --json              emit JSON
  -q, --quiet             suppress progress output
      --demo              render a sample report from invented data
```

Target tags: `default`, `web`, `video`, `dns`, `cdn`, `social`, `messaging`,
`cloud`, `ai`, `dev`, `gaming`, `google`, `telegram`, `all`. You can also name a
specific target, e.g. `-T cloudflare_dns,telegram`.

## JSON

`--json` emits a stable, versioned document for scripting:

```sh
geocheck --json | jq '.connectivity.targets[] | select(.verdict != "direct") | {name, verdict, rtt_ms}'
geocheck --json | jq -r '.consensus.ipv4[0] | "\(.country) \(.percent)%"'
geocheck --json | jq '.findings[] | select(.severity == "alert")'
geocheck --json | jq '.reputation | {type, risk, flags}'
```

Top-level keys: `schema`, `tool`, `timestamp`, `duration_ms`, `identity`,
`transport`, `findings`, `reputation`, `consensus`, `geo`,
`connectivity_checks`, `connectivity`, `stash_checks`.

`--demo --json` produces the same document from the sample data, which is a
convenient fixture to develop against.

## Contributing

See [DEVELOPMENT.md](https://github.com/remnawave/geocheck/blob/main/DEVELOPMENT.md)
for the build, the repository layout, the release process and the known
limitations.

<div align="center">
<a href="https://github.com/remnawave/geocheck/graphs/contributors">
<img src="https://contrib.rocks/image?repo=remnawave/geocheck" alt="Contributors">
</a>
</div>

## Star history

<div align="center">
<a href="https://star-history.com/#remnawave/geocheck&Date">
<picture>
<source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=remnawave/geocheck&type=Date&theme=dark">
<source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=remnawave/geocheck&type=Date">
<img src="https://api.star-history.com/svg?repos=remnawave/geocheck&type=Date" alt="Star history chart" width="620">
</picture>
</a>
</div>

## Thanks

This project stands on work done by others:

- [ipregion](https://github.com/Davoyan/ipregion) by Davoyan, and
  [vernette/ipregion](https://github.com/vernette/ipregion) before it
- [StashNetworks/misc](https://github.com/StashNetworks/misc)
- [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)
- [proxycheck.io](https://proxycheck.io) and
  [Team Cymru](https://team-cymru.com/community-services/ip-asn-mapping/) for
  keeping their services usable without an account
- [charmbracelet/vhs](https://github.com/charmbracelet/vhs), which records the
  animations above

## License

MIT – see [LICENSE](https://github.com/remnawave/geocheck/blob/main/LICENSE).
