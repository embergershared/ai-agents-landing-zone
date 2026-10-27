# Changelog

What changed for users of ai-agents-landing-zone, newest first. Each merged PR adds its line under
**Unreleased** (with its issue number); a release moves them under a dated version.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added
- Repository created from [embergershared/repo-template](https://github.com/embergershared/repo-template).
- README explains the Agent Landing Zone, its Bicep and Terraform implementations and their limits (#3).
- Deployment plan for the Agent Landing Zone with Terraform on public endpoints, without AI Gateway, with a switch
  for the Foundry Agent Service dependencies (#3).
- Deployment plan groups the resources in three: Foundry essentials, Agent Service dependencies, and workload (#25).
