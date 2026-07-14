# Patch process diagram

```mermaid
flowchart TD
  A[Patch Tuesday / application update starts] --> B[Build and test a new image]
  B --> C[Publish immutable Azure Compute Gallery version]
  C --> D[Approve and pin the image version for rollout]
  D --> E[Terraform plan or Bicep what-if]
  E --> F[Deploy new numbered generation (1-100 hosts max)]
  F --> G[Validate AVD registration and application readiness]
  G --> H{Pilot successful?}
  H -- No --> I[Rollback: re-enable previous generation and retire failed new generation]
  H -- Yes --> J[Place old generation in drain mode]
  J --> K[Review active sessions]
  K --> L{Explicit approval to log off users?}
  L -- No --> M[Wait for sessions to drain naturally]
  L -- Yes --> N[Log off remaining users with confirmation]
  M --> O[Retire old infrastructure in separate operation]
  N --> O
  O --> P[Remove old AVD registrations]
  P --> Q[Close change window]
```
