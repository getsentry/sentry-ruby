---
name: Bug report
about: Create a report to help us improve
title: ''
labels: bug
assignees: st0012
body:
  - type: markdown
    attributes:
      label: Issue Description
    validations:
      required: true
  - type: markdown
    attributes:
      label: Reproduction Steps
    validations:
      required: true
  - type: markdown
    attributes:
      label: Expected Behavior
    validations:
      required: true
  - type: markdown
    attributes:
      label: Actual Behavior
    validations:
      required: true
  - type: input
    attributes:
      label: Ruby Version
    validations:
      required: true
  - type: input
    attributes:
      label: SDK Version
    validations:
      required: true
  - type: input
    attributes:
      label: Integration and Its Version
      description: e.g. Rails/Sidekiq/Rake/DelayedJob...etc.
    validations:
      required: false
  - type: markdown
    attributes:
      label: Sentry Config
    validations:
      required: false
---
