# Changes

## 3.9.0 — review fixes (2026-09-24)

- Preserve existing WordPress sites, database administrator credentials and services
  on failures. New sites use `/var/www/wordpress`, private fresh downloads, required
  distro PHP packages, locally generated salts before bootstrap, and validated
  Apache configuration. Added Alpine/OpenRC support and SELinux content labeling.
- Preserve Docker JSON and existing network addressing when changing MTU. Support
  Netplan, NetworkManager, ifupdown, sysconfig and networkd; fix probe selection and
  cancellation, and refuse invalid JSON or unsupported network definitions.
- Update only when Git can fast-forward; avoid restart loops for local commits.
  Store settings and update summaries atomically. Use explicit privilege metadata.
- Update Docker-Prep, LinUtil, Xen Orchestra, cloudflared and UniFi pins. Verify
  downloads and commits, peel annotated tags, retain the trusted manifest during
  runtime update checks, and prevent UniFi from replacing its tracked script.
- Correct RHEL detection, Arch complete-update behavior, DNF4/DNF5 timers, Alpine
  scheduler activation and failure recovery, and SUSE rolling-release maintenance.
  Arch and SUSE guest utilities can use the generic trusted ISO payload.
- Restrict guest-tool mount cleanup to owned mounts. Preserve SSH key line endings,
  restricted-key options and ownership with atomic replacement. Validate SSH daemon
  configuration before banner changes and put global directives before Match blocks.
- Add failure and distro regression tests, Linux container CI, pinned Actions,
  Dependabot, upstream provenance, and LF checkout rules.

Validation records are in `REVIEW.md`. Container regressions mock package and
service operations; full VM installation/service/reboot testing remains separate.
