Review pull request #$ARGUMENTS following these steps:

1. Fetch PR metadata: `gh pr view $ARGUMENTS --json title,body,files,additions,deletions,commits`
2. Fetch full diff: `gh pr diff $ARGUMENTS`
3. Check existing reviews: `gh pr view $ARGUMENTS --json reviews,reviewRequests`

Review criteria (high to low priority):
- Security vulnerabilities (red dot)
- Logic errors and bugs (red dot)
- Data integrity issues (soft-delete filters, missing validations) (orange dot)
- Performance concerns (orange dot)
- Code quality and conventions (yellow dot)
- Documentation gaps (yellow dot)

For each finding:
- Use importance emojis (red/orange/yellow dots)
- Include project name, file path, line number
- Provide code suggestion for the fix
