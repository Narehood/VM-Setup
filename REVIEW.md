# VM-Setup review

Reviewed September 24, 2026, against `main` at `b8acab951a0d74e20f866c7d73dd52c3a20e3749` (VM-Setup 3.8.1). The clone matched GitHub's `main` when fetched, and a fresh fetch during implementation confirmed the same upstream commit.

## Implementation status — 3.9.0

The 18 findings below describe the original commit. Fixes are implemented on
`fix/review-hardening-updates`; the original findings are retained as an audit trail.

| Findings | Implemented change | Regression coverage |
| --- | --- | --- |
| 1, 5, 13 | WordPress owns only newly created resources; fresh private archive; required distro PHP packages; no root DB password replacement | Existing-site/credential preservation, selective DB cleanup, archive staging, package failure propagation, distro dispatch |
| 2 | Parser-required, backed-up, atomic Docker JSON edits | Preserve unrelated keys, reset, malformed JSON and missing parser |
| 3, 8 | Docker pin stays immutable; updates are run-once; annotated tags are peeled | Real local Git tags, prerelease rejection, offline behavior, unchanged manifest |
| 4 | UniFi updated to 9.2.3; external TLS validation; no script self-update/deletion | Verified upstream digest, reproducible hardening, syntax and static checks |
| 6 | No Arch metadata-only refresh before partial installs; explicit complete system upgrade | Installer/update/scheduler command capture |
| 7 | Launch actual versioned LinUtil binaries with SHA-256 verification | Architecture selection, corrupt binary rejection; both downloaded assets hashed and ELF linkage inspected |
| 9 | Classify Git ancestry; fast-forward only; restart only after change | Real equal/ahead/behind/diverged repos, dirty checkout, single restart |
| 10, 11 | Largest successful MTU probe; bounded probes; detected backend; preserve addressing | Probe success/failure/cancel; static ifupdown, NM UUID, sysconfig, networkd, Netplan YAML matching |
| 12 | Private owned guest-tool mount; no global `/mnt` cleanup | No unmount on source/unused cleanup; owned mount only |
| 14, 15 | RHEL dispatch, root without sudo, DNF4/5, OpenRC and cron activation | 15 distro IDs; root-helper/scheduler command capture |
| 16 | Explicit successful returns for no-reboot/quiet/no-log paths | Function exit status and lock ownership fixtures |
| 17 | Inherited ERR handler and repository-only recovery instructions | Failure inside nested function invokes actual recovery handler |
| 18 | Newline-safe SSH merge and atomic replacement | Missing final newline, deduplication, restricted-key preservation |

Additional changes include SSH banner validation, current upstream pins, protected
tunnel token files, explicit root metadata, atomic settings, LF checkout rules,
warning-level first-party ShellCheck, pinned Actions, Dependabot and Linux CI jobs.
See [CHANGELOG.md](CHANGELOG.md) and [UPSTREAM.md](UPSTREAM.md).

Final local validation: the complete `tests/security-checks.sh` suite passed,
including syntax checks, seven subordinate regression suites and all 15 installer
checksums. First-party ShellCheck runs at warning severity; the vendored UniFi
script runs at error severity. Workflow YAML and the UniFi patch's Python syntax
were parsed. Netplan's YAML matching test ran with PyYAML available.

Local checks run under Git Bash on Windows. Linux CI jobs have been added but have
not been executed from this workspace. Native package installation, guest ISO
installation, systemd/OpenRC activation, SELinux/AppArmor behavior, real MTU changes
and reboot recovery still require disposable Linux VMs. Third-party tools retain
their upstream OS limits; this is not certification of every OS/application pair.

## Original review

The most valuable work is correcting data preservation, installer integrity, and failure handling. Performance improvements should follow those fixes. The existing checksum checks, explicit update preferences, fast-forward updates, and Alpine upgrade helpers provide a useful foundation, but passing the current tests does not establish that installation and recovery paths work.

**Scope and validation**

Reviewed the main menu, all first-party modules, third-party launchers, settings, documentation, five test scripts, maintenance tools, and both workflows. The large vendored UniFi installer received static analysis and targeted review of privilege checks, downloads, updates, and cleanup; this is not an exhaustive audit of its entire installation engine or upstream dependencies.

- All 23 shell files passed `bash -n`.
- `bash tests/security-checks.sh` passed, including all four subordinate test scripts and all 15 installer checksums.
- ShellCheck 0.11.0, at warning severity, reported zero errors and 20 warnings. Several warnings are limitations of following dynamically sourced test helpers; the count should not be treated as 20 confirmed bugs.
- Temporary fixtures reproduced the WordPress rollback, Docker configuration loss, checksum rebaselining, annotated-tag failure, update/restart cycle, MTU probe failures, false reboot-check failure, missing Alpine recovery handler, and unrelated mount cleanup. Additional checks confirmed RHEL classification and ignored PHP installation failures.
- Tests ran with Git Bash on Windows using an export of the committed LF bytes. The Windows checkout uses automatic CRLF conversion; the initial export inherited that setting, so it was recreated with conversion disabled before obtaining the passing result above. Committed checksums are correct.
- No real package installation, service restart, network change, OS upgrade, or destructive installer operation was performed. Destructive commands in reproductions were mocked. Actual distribution behavior still needs disposable Linux VMs; neither WSL nor Docker was available here.

**Prioritized findings**

1. **P1 — Refusing to reinstall WordPress can delete the existing site.** [WordPress.sh:73](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/WordPress.sh#L73), [WordPress.sh:121](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/WordPress.sh#L121).

   `INSTALLATION_FAILED=1` and the EXIT trap are installed before preflight. Finding an existing `wp-config.php` exits, then `cleanup()` runs `rm -rf "${INSTALL_DIR:?}"/*` against that existing site. It also removes `/root/.my.cnf` and the credentials file regardless of who created them. A failure before any installation can therefore destroy unrelated content. The fixture confirmed that an existing-site refusal reaches these deletion commands. Complete preflight before enabling rollback, record exactly which resources this run creates, and restore backups instead of deleting a shared document root. Preserve existing database administrator credentials and service state.

2. **P1 — Changing Docker MTU can discard every other daemon setting.** [mtu-fix.sh:411](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/mtu-fix.sh#L411).

   When `jq` is absent, `update_docker_json()` overwrites an existing file with only `{"mtu": ...}`. The fixture lost both `data-root` and `log-driver`. This can change where Docker looks for its data on restart. The reset path's line-based `sed` fallback can also leave invalid JSON. Require a real JSON parser, reject malformed input, preserve every unrelated key, back up the file, validate the result, and atomically replace it. [Docker documents `data-root` and daemon configuration here](https://docs.docker.com/engine/daemon/).

3. **P1 — A Docker-Prep pin update silently trusts changes to every installer.** [Docker-Prep.sh:95](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/Docker-Prep.sh#L95), [Docker-Prep.sh:137](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/Docker-Prep.sh#L137).

   Accepting a pin update rewrites the tracked launcher and runs the maintainer checksum generator over all installers. An unrelated modified WordPress script failed verification before this refresh and passed afterward in the fixture. This defeats the intended protection against modified installers and makes ordinary application use dirty the Git checkout. Keep runtime pin preferences outside tracked scripts, validate them as data, and reserve full manifest regeneration for reviewed maintenance changes. If a local override is supported, display it explicitly and verify the external commit without rewriting the trusted manifest.

4. **P1 — UniFi can disable TLS authentication before downloading code run as root.** [UniFi-Controller.sh:386](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/UniFi-Controller.sh#L386), [UniFi-Controller.sh:3112](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/UniFi-Controller.sh#L3112).

   A failed TLS probe sets shared curl arguments to `--insecure`. Those arguments are reused to download replacement installer code and its checksum; fetching both through unauthenticated transport does not authenticate the result. The updater also executes a download when no checksum is available. Separately, its normal self-update replaces the tracked installer, so a later menu launch can fail the committed checksum check. Fail on certificate/authentication errors, require authenticated integrity metadata, and integrate upstream updates as reviewed revisions. Run vendor code from a verified temporary copy if it otherwise edits or removes itself. [curl explains that `--insecure` disables peer verification](https://curl.se/docs/sslcerts.html).

5. **P1 — WordPress trusts a predictable archive in shared `/tmp`.** [WordPress.sh:643](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/WordPress.sh#L643).

   Any existing `/tmp/latest.tar.gz` is accepted without checking its provenance and extracted into the web root by a root process. A pre-positioned archive can supply the PHP application that gets deployed; an interrupted earlier download can also cause failure and trigger the unsafe cleanup above. Download into a private `mktemp -d` directory, require successful completion, validate the archive and expected contents, and clean up only that invocation's files.

6. **P1 — Arch maintenance creates an unsupported partial-upgrade situation.** [Automated-Security-Patches.sh:108](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/Automated-Security-Patches.sh#L108), [serverSetup.sh:159](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/serverSetup.sh#L159), [WordPress.sh:184](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/WordPress.sh#L184).

   The daily service runs `pacman -Syy` without upgrading installed packages; later `pacman -S` installations can mix repository generations. Initial setup and WordPress similarly refresh before installing a subset of packages. Use `checkupdates` for notification-only maintenance, and explicitly plan a complete upgrade when synchronizing repositories for installation. Do not silently introduce a full upgrade as the fix. [Arch's maintenance guidance describes this failure mode and the safer check command](https://wiki.archlinux.org/title/System_maintenance#Partial_upgrades_are_unsupported).

7. **P2 — LinUtil's pinned entrypoint does not exist.** [linutil.sh:49](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/linutil.sh#L49).

   The launcher requires `linutil.sh`, but the exact pinned upstream tree contains `start.sh`, not `linutil.sh`. The option fails after a successful fetch. Merely renaming the command is insufficient for reproducibility: upstream `start.sh` downloads a latest-release binary when Cargo is unavailable. Choose either a pinned, verified release artifact or a deliberate build of the pinned source with locked dependencies. Add a smoke test that verifies the actual upstream entrypoint. [Pinned upstream launcher](https://github.com/ChrisTitusTech/linutil/blob/41fc99189a588bfa82190fe49a1baf23fd65e97f/start.sh).

8. **P2 — Docker-Prep updates fail for annotated release tags.** [Docker-Prep.sh:37](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/Docker-Prep.sh#L37), [Docker-Prep.sh:183](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/Docker-Prep.sh#L183).

   `ls-remote --tags --refs` returns the annotated tag object's ID. Checkout resolves it to a commit, so comparing `HEAD` against that tag ID fails. A local annotated-tag fixture reproduced the rejection. Peel the selected tag to its commit and store/compare commit IDs consistently. The CI pin-sync helper already handles an annotated tag separately. Also filter prereleases deliberately rather than treating every `v*` tag as a stable release. [Git documents the peeled-tag distinction](https://git-scm.com/docs/git-ls-remote#_output).

9. **P2 — A locally ahead branch repeatedly triggers automatic updates.** [install.sh:656](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/install.sh#L656), [install.sh:590](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/install.sh#L590).

   Any unequal local/upstream hashes are treated as an available update. For a clean branch with a local commit and nothing upstream, `git pull --ff-only` succeeds without changing HEAD, yet the menu records an update and restarts. Startup repeats the same decision after the update-summary prompt. Two simulated launches confirmed it. Classify equal/ahead/behind/diverged histories, update only when behind and fast-forwardable, and restart only when HEAD actually changed. Merge the already-fetched revision to avoid a redundant fetch and changing the target between checking and applying.

10. **P2 — The MTU test option does not return a usable recommendation.** [mtu-fix.sh:555](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/mtu-fix.sh#L555), [mtu-fix.sh:623](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/mtu-fix.sh#L623).

   Three failures were reproduced: all successful probes recommend the smallest value (`1100`); a failed first probe (`1500`) stops before testing smaller values; and captured stdout contains status messages alongside the number subsequently passed to `ip link`. Print diagnostics to stderr, return exactly one validated number, and use the first successful value when testing downward. Bound ping duration and distinguish ICMP blocking from an MTU limitation. Handle cancellation with an explicit conditional so `set -e` does not terminate the fallback path.

11. **P2 — Persistent MTU configuration selects the wrong backend on Netplan hosts.** [mtu-fix.sh:224](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/mtu-fix.sh#L224).

   Every Debian-family system is configured through `/etc/network/interfaces`; when missing, the script invents a DHCP stanza. On a host managed by Netplan this does not update the active configuration, despite the final persistence claim. Detect the active network manager and preserve the existing addressing configuration. Use the matching Netplan, NetworkManager, networkd, or ifupdown mechanism, with backup and a recovery path for remote sessions. [Ubuntu documents Netplan as its network configuration layer](https://ubuntu.com/server/docs/explanation/networking/about-netplan/).

12. **P2 — Initial setup can unmount an unrelated filesystem.** [serverSetup.sh:79](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/serverSetup.sh#L79), [serverSetup.sh:245](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/serverSetup.sh#L245).

   The unconditional EXIT trap unmounts `/mnt` whenever it is a mountpoint, even if this invocation never mounted an ISO. This includes help/version exits and sourcing the script from tests. The ISO path also explicitly unmounts any existing `/mnt` mount. A mock fixture confirmed cleanup attempts the unmount after sourcing only. Use a dedicated mount directory and an ownership flag; install cleanup traps only in executed main code.

13. **P2 — WordPress proceeds after required PHP packages fail to install.** [WordPress.sh:575](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/WordPress.sh#L575).

   Every PHP package failure is downgraded to a warning and followed by “All packages installed.” A fixture with every PHP installation failing still produced that success message. Version selection also guesses candidates when repository discovery returns nothing. Distinguish required components from optional extensions, refresh metadata before discovering candidates, abort if required packages fail, and verify the PHP handler, database extension, web-server configuration, and HTTP behavior before declaring success. Install preflight dependencies before using them; password generation currently invokes OpenSSL before the package installation phase.

14. **P2 — RHEL is advertised but rejected by several modules.** [serverSetup.sh:131](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/serverSetup.sh#L131), [WordPress.sh:156](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/WordPress.sh#L156), [mtu-fix.sh:118](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/mtu-fix.sh#L118), [systemUpdate.sh:200](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/systemUpdate.sh#L200).

   These helpers/case statements recognize `redhat` but omit `rhel`, whereas other modules recognize `rhel`. Setting `OS=rhel` reproduced the three helper failures. Centralize OS-family detection, use `ID_LIKE` where appropriate, and test the actual IDs supported by each module rather than duplicating slightly different lists.

15. **P2 — Automatic updates require sudo even when already root.** [Automated-Security-Patches.sh:15](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/Automated-Security-Patches.sh#L15), [Automated-Security-Patches.sh:140](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/Automated-Security-Patches.sh#L140).

   The root check accepts a root process without sudo, but the installation functions then invoke `sudo` unconditionally. Minimal hosts without sudo fail; initial setup explicitly skips installing sudo on Alpine. Use a shared `run_as_root` helper that executes directly as root and elevates only otherwise. Check that the cron or timer service is actually active before reporting scheduled updates as enabled. Distinguish security-only updates from the full package upgrades scheduled by some backends.

16. **P2 — A successful Debian update can exit as a failure when no reboot is needed.** [systemUpdate.sh:152](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/systemUpdate.sh#L152).

   The Debian branch ends with `[[ -f /var/run/reboot-required ]] && ...`. When absent, the function returns 1; its unguarded call inside `prompt_reboot` triggers `set -e`. The fixture exited 1 for the normal no-reboot case. Return 0 explicitly from informational probes and logging helpers. Similar quiet-mode helpers can return failure when logging is disabled, causing unrelated work to stop.

17. **P2 — Alpine's recovery handler does not catch nested package failures.** [alpineUpgrade.sh:680](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/alpineUpgrade.sh#L680), [alpineUpgrade.sh:527](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/alpineUpgrade.sh#L527).

   The ERR trap is installed in `upgrade_versioned_repos`, but `errtrace` is not enabled for the nested `run_apk_upgrade` function. Injecting an `apk update` failure exited 23 after rewriting repositories without printing the recovery handler's message. Use deliberate error propagation or inherited ERR handling and test failures at each upgrade stage. Retain the backup, but distinguish restoring repository configuration from rolling back already-upgraded packages; they are different operations.

18. **P2 — SSH key import can concatenate two keys into one line.** [github-ssh-keys.sh:242](https://github.com/Narehood/VM-Setup/blob/b8acab951a0d74e20f866c7d73dd52c3a20e3749/Installers/github-ssh-keys.sh#L242).

   Existing content is copied verbatim and new keys appended with `printf`. If `authorized_keys` lacks a trailing newline, the first imported key joins the last existing key, damaging both entries. Normalize the line boundary before appending; validate parsed key material, preserve existing restrictions, and replace the file atomically after validation. The current exact-byte append behavior was reproduced with a fixture.

**Optimization and maintainability suggestions**

- Extract a small shared library for OS detection, privilege handling, logging, prompting, and checksum verification. `install.sh`, `installer.sh`, and `serverConfig.sh` duplicate much of their UI, statistics, and execution behavior. A module registry should explicitly describe supported systems and required privileges; scanning source for commands such as `chmod` can elevate an entire submenu just because it fixes executable bits.
- Put execution behind `main "$@"` and a consistent source guard. Importing functions should not change directories, write settings, install traps, or start menus. This makes behavior tests simpler and prevents the mount side effect above.
- Batch required package installation into one transaction per package manager. WordPress currently starts a separate package-manager process for every base package and PHP extension. Preserve command output in a log and show the useful error tail on failure; much of the installer currently discards diagnostics.
- Consolidate metadata reads: parse `/etc/os-release` once per useful refresh, read update-state files in one pass, and share system-stat collection across menus. Refresh hostname after hostname changes rather than retaining the startup value indefinitely. These are modest responsiveness improvements; package transactions and network fetches are the larger costs.
- Give every download and Git network operation bounded timeouts and useful failure messages. Cache immutable, verified external revisions if repeated launcher downloads are significant, but reverify the cache before execution.
- Use atomic writes and resource ownership tracking for settings, SSH keys, Docker JSON, network files, and update state. Replace PID-file check/write locks with a proven atomic lock approach. Serialize configuration changes that can conflict with scheduled package maintenance.
- Make the external-code policy consistent. Xen Orchestra still pulls and executes a moving checkout, while the README broadly describes pinned third-party launchers. Pin the executable revision, verify the expected repository and clean state, and reject failed fetches rather than continuing into stale or conflicted code.
- Before SSH or web-server reloads, validate the generated configuration and retain the original. MOTD's backup function does not currently back up `sshd_config`, even though the banner operations edit it; an appended Banner directive can also land inside an existing Match block.
- Add `.gitattributes` with LF rules for shell scripts and the checksum manifest, plus an EditorConfig. The Windows checkout demonstrated how platform line endings can obstruct validation even though committed bytes are correct.
- Pin GitHub Actions to reviewed commit SHAs and use dependency automation for updates. Keep third-party vendor provenance and local patches explicit. Raise first-party ShellCheck coverage to warning severity after triage rather than ignoring all warnings globally.

**Tests worth adding first**

Replace string-presence assertions with tests calling production helpers. For example, `tests/docker-prep-update.sh` duplicates the tag-selection pipeline rather than exercising `resolve_latest_docker_prep`; `tests/update-flow.sh` mostly checks text and synthetic state instead of performing repository updates.

| Area | Meaningful regression cases |
| --- | --- |
| WordPress | Existing site refusal preserves every file; package/download failure preserves unrelated services and credentials; pre-existing shared temporary archive is ignored |
| Docker MTU | Missing jq, malformed JSON, nested unrelated settings, and reset all preserve valid configuration |
| Repository updates | Equal, behind, ahead, diverged, dirty, failed fetch, and no-op pull; restart only after a changed commit |
| External launchers | Lightweight and annotated tags, prereleases, missing entrypoint, checksum failure, and unchanged tracked files |
| System configuration | No reboot needed; root without sudo; OS-family table; no default route; MTU search and cancellation; existing SSH file without final newline |
| Alpine and mounts | Every package phase fails independently; recovery details appear; only mounts created by this invocation are unmounted |

Use containers for helper/package compatibility where appropriate and disposable VMs for systemd/OpenRC, networking, SSH, guest tools, and OS upgrades. Start with the distributions actually used in your environment, then expand the support matrix based on passing evidence.

Suggested implementation order: preserve existing data/configuration first (1–5), correct update and launch behavior (7–9), fix distro/network/service paths, then consolidate shared code and improve performance. Add the relevant regression test alongside each correction.
