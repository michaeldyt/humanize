# Independent Review Failed

The independent review process failed to produce valid output.

**Reason**: {{FAILURE_REASON}}
**Round**: {{ROUND_NUMBER}}
**Base Branch**: {{BASE_BRANCH}}
**Exit Code**: {{EXIT_CODE}}
**Review Result File**: {{REVIEW_RESULT_FILE}}

**Debug Files**:
- Command: {{CODEX_CMD_FILE}}
- Log: {{CODEX_LOG_FILE}}

**Stderr (last 50 lines)**:
```
{{STDERR_CONTENT}}
```

Please check the debug files for more details. The system will attempt another independent review when you exit.
