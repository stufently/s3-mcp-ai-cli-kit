# Changelog

## 2026-10-14

- Add provider catalog templates for Glama metadata, Desktop Extension bundles, image labels and MCP Registry publishing.
- Add a catalog self-test that guards scaffold rendering, bundle prechecks and static acceptance checks.
- Extend the catalog self-test to catch the seven mutants left by the milestone 2a acceptance run.

## 2026-10-11

- Add directory ownership verification for Google Search Console and IndexNow.

- Add a bilingual directory linking all seven S3 MCP servers and their provider guides.
- Add a static GitHub Pages site and social preview artwork for the project family.

## 0.1.1

- Disable bucket creation, deletion and configuration tools independently for console-only providers, including direct CLI/core calls before network access.
- Keep existing profiles compatible when the new bucket capabilities are omitted.
- Expand registration coverage to 32768 capability/permission/file-root combinations and add eight protective mutations (95 total).
- Provision emulator fixtures separately from console-only provider operations.

## 0.1.0

- Extract the shared S3 MCP server, tool registry, streaming CLI and atomic client/skill installers.
- Preserve scoped access, confined file operations, signed one-use human approval, secret redaction and private audit.
- Decode embedded YAML profiles and render provider-specific skills from shared templates.
- Refuse unprotected default writes and disable move without conditional delete support.
- Provide reusable Docker conformance, exhaustive capability/permission registration tests, 87 mutation checks and provider CI.
