# Contributing

## Principles

- Keep generation deployments and retirement steps separate.
- Pin Azure Compute Gallery image versions or marketplace versions; never rely on mutable `latest` in production rollouts.
- Validate Terraform, Bicep, and PowerShell changes locally before opening a pull request.
- Do not commit secrets, live registration tokens, customer identifiers, or production parameter files.

## Local validation

```bash
terraform -chdir=terraform/environments/example init -backend=false
terraform -chdir=terraform/environments/example fmt -check -recursive
terraform -chdir=terraform/environments/example validate
bicep build bicep/main.bicep
pwsh -NoLogo -NoProfile -Command "Invoke-ScriptAnalyzer -Path ./scripts -Recurse -Severity Error"
```

## Pull requests

1. Explain the generation being introduced or the operator workflow being changed.
2. Call out any changes to required RBAC, managed identities, image references, or retirement guidance.
3. Include validation results and note any follow-up limitations.
