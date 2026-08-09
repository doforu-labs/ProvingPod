# Contributing

Thanks for helping with ProvingPod!

## Scope

ProvingPod is a zero-cost proving-pod service for AI-generated code: SSH in, get an isolated
container (node + desktop + Chrome + noVNC), prove it runs, throw it away. Keep contributions
within that scope — a small, focused tool beats a sprawling one.

## How to contribute

1. Fork the repo and create a branch: `git checkout -b feat/your-change`
2. Make the change; keep scripts POSIX-sh/bash compatible where possible.
3. Test what you changed:
   - Shell scripts: `shellcheck gateway/*.sh userenv/*.sh deploy/*.sh`
   - Images build: `docker build --network host -t proving-gw:v1 gateway/` and
     `docker build --network host -t proving-pod:v1 userenv/`
   - If you changed runtime behavior, verify the end-to-end flow from `README.md`
     (SSH login, command pass-through, `-tt` interactive login, noVNC, TTL cleanup).
4. Open a PR with a clear description. Reference the checklist above in the PR body.

## Guidelines

- **No secrets in code.** The default password `123456` and `vncpass` are intentionally public
  for the throwaway-pod design — if you touch auth, keep it compatible with
  `SECURITY.md`'s hardening story.
- Keep the Docker edition (`gateway/`, `userenv/`, `deploy/`) the single supported path; the
  `incus/` directory is legacy reference only — don't build new features on it.
- Update docs (`README.md`, `docs/service-usage.md`) when user-facing behavior changes.

## Code of conduct

Be respectful, constructive, and assume good faith. No harassment, no spam.
