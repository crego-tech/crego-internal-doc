# Crego Internal Documentation

Central knowledge base for Crego engineering, architecture, compliance, and operations documentation.

## Sections

| Folder                                                            | Description                                                                               |
| ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| [architecture](architecture/README.md)                            | System architecture, deployment topology, multi-tenancy, request flow, and tech stack     |
| [engineering](engineering/sdlc-development-guide.md)              | SDLC guide, deployment guide, remote access, utility commands, platform overview          |
| [git-strategy](git-strategy/README.md)                            | Git branching & merge strategy, workflow guides, client version management                |
| [release-management](release-management/team-release-playbook.md) | Release process setup, team playbook, tracker, and per-version release notes              |
| [compliance](compliance/README.md)                                | Security audits, DR drill reports, network architecture, audit policies (PDFs + markdown) |
| [infrastructure](infrastructure/platform-ips.md)                  | Platform IPs and credentials reference                                                    |
| [hiring](hiring/ai-developer-assignment.md)                       | Interview question sets and developer assignments                                         |
| [onboarding](onboarding/README.md)                                | New developer onboarding guides                                                           |
| [runbooks](runbooks/README.md)                                    | Operational runbooks (deploy, rollback, DR, scale, etc.)                                  |
| [_archive](_archive/README.md)                                    | Deprecated or orphaned files pending review/deletion                                      |

## Quick Links

- **Release Playbook:** [team-release-playbook.md](release-management/team-release-playbook.md)
- **System Architecture:** [01-system-architecture.md](architecture/high-level-design/01-system-architecture.md)
- **Git Branching Guide:** [git-strategy/README.md](git-strategy/README.md)
- **SDLC & Dev Guide:** [sdlc-development-guide.md](engineering/sdlc-development-guide.md)
- **Deployment Guide:** [deployment-guide.md](engineering/deployment-guide.md)
- **Release Tracker (Google Sheets):** [Live Tracker](https://docs.google.com/spreadsheets/d/1d_QuK-DRVkIMkQLqR4P_RGprrFQOM5iCkat1aavx5Tg/edit?gid=1061338283#gid=1061338283)

## Security Notice

The `infrastructure/credentials.md` file contains plaintext credentials for Grafana and ArgoCD environments. These should be migrated to a secrets manager (1Password, HashiCorp Vault, etc.) and replaced with access instructions. **Do not add new credentials to this file.**

## Contributing

- All internal docs live in this repository (Obsidian-compatible vault)
- Use lowercase folder names and kebab-case filenames
- Remove Notion export hash suffixes from any imported files
- See the workspace [CLAUDE.md](../CLAUDE.md) for the full repository map
