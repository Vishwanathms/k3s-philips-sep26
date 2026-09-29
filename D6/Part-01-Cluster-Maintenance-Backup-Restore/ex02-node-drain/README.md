# ex02 — node drain

No manifests here — this lab runs `kubectl drain` against the live node,
using `--dry-run=client` so it's 100% safe on a single-node cluster (a real
drain here would evict Traefik, CoreDNS, the CSI controller, etc. with
nowhere else to reschedule to, since there's only one node). The output is
completely real — dry-run only skips the last step (actually cordoning the
node and evicting pods).

Run `../LAB-MANUAL.md`'s Lab 2. Captured real output in
[OUTPUT.md](OUTPUT.md).
