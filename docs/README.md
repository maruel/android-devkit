# Android Devkit documentation

This documentation separates reproducible evidence from working hypotheses for
the Pico i.MX7 work. It does **not** claim that an image has been built or
flashed successfully.

## Start here

1. Read [workflow status and prerequisites](workflow-status.md). It states the
   unresolved choices that must be made before a build or flash is attempted.
2. Use the [Yocto workflow evidence](workflows/yocto.md) or the
   [Ubuntu image and kernel evidence](workflows/ubuntu.md) only after checking
   their cited source notes.
3. Follow [safe flashing](workflows/flashing.md) for the recorded UUU process;
   it deliberately requires an explicit device and artifact confirmation.
4. Phase 2 implementers must follow the
   [workflow implementation contract](contracts/phase-2-workflow.md).
5. Use the [fail-closed workflow helpers](workflow-helpers.md) only after all
   selections in the workflow status are resolved and entered explicitly.

## Documentation map

- [Workflow status and authority](workflow-status.md) — what is known, what is
  only a report, and the blocking decisions.
- [Fail-closed workflow helpers](workflow-helpers.md) — strict manifest setup,
  individual helper commands, outputs, and guarded flashing behavior.
- [Yocto workflow evidence](workflows/yocto.md) — recorded manifest, machine,
  image, and Wi-Fi customization notes.
- [Ubuntu image and kernel evidence](workflows/ubuntu.md) — recorded base-image,
  config-extraction, Wi-Fi, and camera investigation notes.
- [Safe flashing](workflows/flashing.md) — UUU evidence and non-negotiable
  target-selection safeguards.
- [Alternative OS references](references/alternative-oses.md) — non-selected
  research leads.
- [Wi-Fi and camera evidence](references/components.md) — component-specific
  facts, hypotheses, and gaps.
- [Raw source notes](source-notes/index.md) — preserved provenance, not an approved
  runbook.

Every statement in the curated pages is qualified by a link to a raw source
note. External URLs in those notes are leads to verify, not facts newly
validated by this repository.
