# Development

## Building

```sh
make help              # list every target
make build             # host binary
make check             # format, lint, test
make test              # go test -race
make release-snapshot  # cross-compile all four platforms into dist/
make docker            # build the container image
```

Go 1.26 or newer. There are no code-generation steps and no CGO: `go build ./...`
on its own works.

## Repository layout

```
cmd/geocheck           entrypoint
internal/netx          HTTP/dialer stack: family pinning, interface binding, SOCKS5, DoH
internal/geo           geolocation providers and the concurrent check runner
internal/reputation    proxycheck.io address classification
internal/portal        captive-portal / NCSI endpoint catalogue
internal/access        service-availability probes
internal/mtr           ICMP engine, target catalogue, path classification
internal/asn           IP-to-ASN over Team Cymru's DNS service
internal/detect        tunnel and DNS interception checks
internal/render        terminal report and JSON output
scripts/               the geocheck.ing launcher and its build step
web/                   Cloudflare Worker serving geocheck.ing
```

## Privileges, and why the Dockerfile does what it does

Hop-by-hop tracing needs a raw ICMP socket.

The image carries the capability as `cap_net_raw+p` (permitted) rather than
`+ep` (permitted and effective) on purpose. With the effective bit set by the
file capability, the kernel refuses to _exec_ the binary at all whenever
`NET_RAW` is outside the bounding set – so `docker run --cap-drop=ALL` would fail
before `main()` runs. geocheck raises the bit itself when it is allowed to.

Two consequences worth knowing when changing this code:

- **Linux capabilities are per-thread.** `raisePrivilege()` acts on the calling
  thread only, so `openICMPSocket` pins the goroutine with `runtime.LockOSThread`
  for the whole raise-then-socket sequence. Without the pin the Go scheduler can
  move the goroutine between the two calls and the raw socket fails with EPERM –
  intermittently, which looks like a flaky network rather than a scheduling race.
- **Unprivileged Linux ping sockets never receive `TimeExceeded`.** The kernel
  diverts ICMP errors to the socket error queue, reachable only through
  `IP_RECVERR` and `MSG_ERRQUEUE`, which `golang.org/x/net` does not expose.
  Rather than print a path of stars, geocheck detects the situation and falls
  back to TCP with an explanation.

## Testing

```sh
make test                    # -race, all packages
go test ./internal/mtr/ -run Classify -v
```

The classification tests encode decisions that are easy to get wrong twice, in
particular that a sub-millisecond reply behind a real multi-hop path is `direct`
(an on-net cache in a datacenter) while the same latency at the first TTL is
`intercepted`. Do not "simplify" those into a single threshold.

The launcher has its own CI job that shellchecks it, parses it under `dash` as
well as `sh`, and verifies the Cloudflare Worker serves it **byte-identically**
to the file in the repository.

## Cutting a release

`VERSION` holds the release number and is the single source of truth.

```sh
make version           # show the current version and the image it maps to
make release-patch     # 0.1.0 -> 0.1.1, commit, tag, push
make release-minor     # 0.1.0 -> 0.2.0, commit, tag, push
make release-major     # 0.1.0 -> 1.0.0, commit, tag, push
```

To review the commit before publishing, do it in two steps:

```sh
make bump-minor        # rewrite VERSION and commit, nothing pushed
git show               # check it
make tag               # tag and push, starting the release
```

Both refuse to run on a dirty working tree and stop if the tag already exists.
`make untag` removes a tag locally and on the remote.

Release tags are **signed**. `make tag` uses `git tag -s`, verifies the
signature before pushing, and refuses to tag at all when no signing key is
configured – an unsigned release tag is worse than no tag, because it looks
authentic. Configure it once:

```sh
git config user.signingkey <key-id>          # GPG
git config gpg.format ssh                    # or SSH, with a signing key
git config user.signingkey ~/.ssh/id_ed25519.pub
```

The push uses `--follow-tags`, so the branch and the annotated tag go together
rather than as two separate pushes that can half-fail.

Pushing the tag triggers `.github/workflows/release.yml`, which builds the
binaries and the GitHub release with GoReleaser, and pushes a multi-architecture
image to Docker Hub as:

- `remnawave/geocheck:ing` – always the current release
- `remnawave/geocheck:latest` – a mirror of it

A prerelease tag (`v0.3.0-rc.1`) publishes only its own exact tag and moves
neither of the rolling ones.

### One-time repository setup

| Secret               | Value                                                       |
| -------------------- | ----------------------------------------------------------- |
| `DOCKERHUB_USERNAME` | Docker Hub account with push rights to `remnawave/geocheck` |
| `DOCKERHUB_TOKEN`    | Docker Hub access token, Read, Write, Delete                |

## geocheck.ing

`scripts/geocheck.sh` is the launcher. It tries, in order: docker, then podman,
then the release archive for the running platform – downloaded to a temporary
directory, checksum-verified against the published `checksums.txt`, run, and
deleted. It installs nothing.

`--runtime auto|docker|podman|binary`, or `GEOCHECK_RUNTIME`, overrides that
order. Naming one makes it a requirement: a missing runtime is an error rather
than a fallback, because someone who asked for podman specifically does not want
docker silently instead. Launcher options are parsed only while they sit at the
front of the argument list and are removed before the rest is handed to
geocheck, so a future geocheck flag cannot be swallowed by the launcher.

It deliberately does _not_ prefer a `geocheck` already on PATH. Someone piping
this script from the network is asking for the current release; deferring to an
installed copy would silently serve a stale one, missing exactly the fixes the
run was meant to pick up. Anyone who has it installed can simply run `geocheck`.

For the same reason it cleans up after itself. An image the run pulled is
removed again afterwards, and the downloaded binary lives in a temporary
directory that the `EXIT` trap deletes – a one-shot invocation should leave no
residue. An image that was _already_ on the machine is never removed: `pulled`
records whether this run is the reason it is there. Removal is by tag, so an
image sharing layers with other tags is merely untagged. `GEOCHECK_KEEP_IMAGE=1`
opts out, which is worth doing if you run it often.

This is why the container is a child process rather than an `exec`: nothing runs
after `exec`, so the cleanup would never happen. The exit status is captured and
re-raised by hand instead, and an `INT`/`TERM` trap covers Ctrl-C.

Because macOS ships as a universal binary (`universal_binaries` in
`.goreleaser.yaml`), its asset is `geocheck_<version>_darwin_all.tar.gz` rather
than one per architecture. Changing that goreleaser setting means changing
`platform_asset` in the launcher to match, or downloads start 404ing.

It clears the screen before handing over, so the report starts at the top rather
than under the pull output. It defers to `clear`, then `tput clear`, then a
literal `ESC[3J ESC[H ESC[2J` – using the terminal's own terminfo where it
exists, and only falling back to hardcoded escapes on a system with neither.
Nothing is written unless stdout is a terminal. `web/worker.js` is a Cloudflare Worker
that serves it: shells (`curl`, `wget`) get the script as `text/plain`, browsers
get a page showing the script in full so it can be read before it is run.

```sh
make web           # embed the script into the Worker
make web-check     # shellcheck + parse checks
make web-deploy    # wrangler deploy, from your machine
```

The script is inlined into the Worker at build time rather than fetched at
request time, so geocheck.ing keeps working when GitHub does not, and so what
the browser displays can never drift from what `curl` receives. CI enforces that
equality.

### Deploying

`.github/workflows/web.yml` deploys automatically on a push to `main` that
touches `scripts/geocheck.sh` or `web/`, and can also be run by hand from the
Actions tab. A Go-only change does not redeploy the site. After deploying it
fetches `https://geocheck.ing` and diffs it against the repository, so a failed
or partial rollout fails the job rather than passing quietly.

Two secrets are required, both under
Settings → Secrets and variables → Actions → **Secrets**:

| Secret                  | Where to get it                                                            |
| ----------------------- | -------------------------------------------------------------------------- |
| `CLOUDFLARE_API_TOKEN`  | Cloudflare dashboard → My Profile → API Tokens → Create Token              |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare dashboard → Workers & Pages → Account ID in the right-hand pane |

The token needs exactly three permissions. Start from **Create Custom Token**
rather than a template, since the "Edit Cloudflare Workers" template grants more
than this needs:

| Type    | Permission      | Level |
| ------- | --------------- | ----- |
| Account | Workers Scripts | Edit  |
| Zone    | Workers Routes  | Edit  |
| Zone    | Zone            | Read  |

Scope it to the one account and to the `geocheck.ing` zone only.

Cloudflare does not document the permissions this particular call needs. The set
above is what worked; if attaching the domain ever fails with a permissions
error, add `Zone → DNS → Edit`, since a Custom Domain creates a DNS record.

### Container runtimes differ on CAP_NET_RAW

The image carries `cap_net_raw` as a file capability, but the kernel only grants
it when the capability is _also_ in the container's bounding set:

```
permitted = bounding AND file_permitted
```

Docker's default capability set includes `CAP_NET_RAW`; podman's does not
(`containers/common`, `DefaultCapabilities` – 11 entries, no NET_RAW). The same
image therefore traces the path under docker and silently falls back to TCP
under podman, reporting no hops at all and printing the unprivileged-socket
warning.

The launcher passes `--cap-add=NET_RAW` for this reason. It is a no-op under
docker, where the capability is already present. Anyone running the image by
hand under podman needs the same flag:

```sh
podman run --rm -it --network host --cap-add=NET_RAW remnawave/geocheck:ing
```

Measured on the same image:

| Invocation                                      | raw socket | hops |
| ----------------------------------------------- | ---------- | ---- |
| `--cap-drop=ALL` (bounding set without NET_RAW) | no         | 1    |
| `--cap-drop=ALL --cap-add=NET_RAW`              | yes        | 2    |
| docker defaults                                 | yes        | 2    |

## Known limitations

- **Flow pinning.** ECMP load balancers hash on fields that vary between probes,
  so a traced path is protocol-specific and can mix parallel routes. geocheck
  surfaces multipath by counting the addresses that answer at each TTL, but does
  not implement full Paris-style flow-identifier pinning.
- **Unprivileged Linux tracing** falls back to TCP; see above.
- **TCP fallback latency.** When a target is measured with a TCP handshake, a
  local proxy or tunnel that terminates the connection itself will make the
  number look better than the real path. The output flags this.
- **IPv6 tracing** is more prone to apparent loss than IPv4, because ICMPv6
  error rate limiting is considerably more aggressive.
- **Endpoint catalogues drift.** The connectivity-check expectations are
  byte-exact assertions; when a vendor changes a response the check reports
  `altered`. Verify against the live endpoint before adjusting a constant, and
  leave an entry out rather than guess at it – a wrong expectation produces a
  false positive, which is worse than no check.
