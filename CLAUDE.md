# CLAUDE.md — Crego Internal Docs

Guide for working within the `crego-internal-docs/` Obsidian vault.

## Structure

This is an Obsidian-compatible vault. Key sections:

- `architecture/` — System design docs with Mermaid diagrams (content is in subfolders: `high-level-design/`, `tenancy-model/`, `data-flow/`)
- `engineering/` — SDLC guide, deployment guide, remote access, utility commands
- `git-strategy/` — Branching and merge strategy, workflow guides
- `release-management/` — Release playbook, setup guide, team structure, checklists, release notes
- `compliance/` — Security audits, DR drills, network architecture (PDFs + markdown)
- `infrastructure/` — Platform IPs and credentials reference
- `hiring/` — Interview questions and developer assignments
- `onboarding/` — New developer onboarding guides
- `runbooks/` — Operational runbooks
- `_archive/` — Deprecated or orphaned files

## Conventions

- Use lowercase folder names and kebab-case filenames
- Links should use standard markdown pointing to specific files (not folder paths)
- Remove Notion export hash suffixes from any imported files
