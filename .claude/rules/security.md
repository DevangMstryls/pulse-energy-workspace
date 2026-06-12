---
description: Security rules applied across all Pulse Energy projects
priority: high
---
# Security Rules

- Never commit API keys, tokens, passwords, or secrets to code
- All secrets must be in environment files (`.dev.env`, `.stg.env`, `.prod.env`) which are gitignored
- Never log sensitive data (tokens, passwords, PII) in any logging statement
- Always validate and sanitize user input at system boundaries
- Use parameterized queries via Prisma — never construct raw SQL with string interpolation
- Never expose internal error stack traces in API responses
- Always use HTTPS for external API calls
- Never disable SSL/TLS verification
- Check for OWASP Top 10 vulnerabilities in any code you write
