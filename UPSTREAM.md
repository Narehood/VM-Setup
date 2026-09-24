# Reviewed upstream versions

Checked September 24, 2026. These are launcher/installer pins, not a claim that
every package installed by third-party tools is pinned or audited.

| Component | Version / immutable revision | Source |
| --- | --- | --- |
| Docker-Prep | `2.4.0-main`, `9b0f944f334b2ba89ce7b5510ea2199d39f3f2b0` | [Repository](https://github.com/Narehood/Docker-Prep/commit/9b0f944f334b2ba89ce7b5510ea2199d39f3f2b0) |
| LinUtil | `2026.07.17`, `7ed1ddb5e9c2733c4f1bb359c7af5dbd08c2261c` | [Stable release](https://github.com/ChrisTitusTech/linutil/releases/tag/2026.07.17) |
| Xen Orchestra installer | `3c2a24b50c6b247b9d330ee151fcdbb42d305083` | [Repository](https://github.com/Narehood/XenOrchestraInstallerUpdater/commit/3c2a24b50c6b247b9d330ee151fcdbb42d305083) |
| cloudflared | `2026.9.3` | [Release](https://github.com/cloudflare/cloudflared/releases/tag/2026.9.3) |
| UniFi installer | Script `9.2.3`, Network `10.6.106` | [Upstream script](https://get.glennr.nl/unifi/install/unifi-10.6.106.sh) |
| actions/checkout | `v7.0.1`, `3d3c42e5aac5ba805825da76410c181273ba90b1` | [Release](https://github.com/actions/checkout/releases/tag/v7.0.1) |
| peter-evans/create-pull-request | `v8.1.1`, `5f6978faf089d4d20b00c7766989d076bb2fc7f1` | [Release](https://github.com/peter-evans/create-pull-request/releases/tag/v8.1.1) |

LinUtil and cloudflared asset SHA-256 digests are stored alongside architecture
selection in their launchers. Digests were checked against GitHub release metadata.
Both LinUtil Linux assets were downloaded, independently hashed, and inspected as
statically linked ELF executables; they were not executed on the Windows review host.

Docker-Prep has no published stable release yet. Its bundled main commit is fixed.
An interactive user can select another discovered commit for one invocation; that
choice never rewrites repository files or regenerates the trusted manifest. Git
annotated tags resolve to their peeled commit. Weekly release sync opens a review PR
once releases exist. Dependabot proposes GitHub Actions updates. LinUtil,
cloudflared, Xen Orchestra and UniFi pins require a maintainer review and checksum
refresh; they do not silently follow moving downloads at launch.

## Vendored UniFi patch

Unmodified upstream SHA-256:
`582e88b863419121aca8af0aaf769f4062fe5f8ff4c04328b0c17eddcfe3d664`.
This matches the [upstream version/checksum API](https://api.glennr.nl/api/latest-script-version?script=unifi-install&version=10.6.106).

The reproducible patch in `tools/harden-unifi.py` requires this exact input digest.
It enforces HTTPS and certificate validation for shared external downloads, removes
explicit external insecure curl options, disables script self-replacement and
self-deletion, and retains local self-signed controller health checks. Those
loopback status checks are distinct from downloaded packages and executable code.
The full vendored installation engine remains third-party code and has not received
an exhaustive security audit.

```bash
curl --fail --location --proto '=https' --proto-redir '=https' \
  https://get.glennr.nl/unifi/install/unifi-10.6.106.sh -o /tmp/unifi-upstream.sh
python3 tools/harden-unifi.py /tmp/unifi-upstream.sh
bash tools/generate-checksums.sh
bash tests/security-checks.sh
```

## Compatibility references

- [Arch system maintenance](https://wiki.archlinux.org/title/System_maintenance):
  complete upgrades and avoidance of partial repository refresh/install workflows.
- [XCP-ng Linux guest tools](https://docs.xcp-ng.org/vms/#linux-guest-tools): native
  packages where available; generic ISO payload for other distributions. The
  [Arch package is in AUR](https://aur.archlinux.org/packages/xe-guest-utilities), so
  VM-Setup uses trusted ISO media instead of asking pacman for an unavailable package.
- [Netplan set](https://netplan.readthedocs.io/en/stable/netplan-set/): staged root
  directory validation and a dedicated MTU override.
- [DNF5 Automatic](https://dnf5.readthedocs.io/en/stable/dnf5_plugins/automatic.8.html):
  modern Fedora timer and security update configuration.
- [Cloudflare tunnel run parameters](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/run-parameters/):
  token file support for service configuration.
