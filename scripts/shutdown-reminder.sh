#!/bin/bash
# Shutdown reminder: uses cast + Claude to generate a personalized wind-down nudge

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

# Load API key
if [ -f "$ENV_FILE" ]; then
    ANTHROPIC_API_KEY=$(grep '^ANTHROPIC_API_KEY=' "$ENV_FILE" | cut -d= -f2-)
fi

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    osascript -e 'display notification "Time to wind down. Sleep beats one more hour of screen time." with title "It'\''s 9:30 PM" sound name "Default"'
    exit 0
fi

# Gather context from today's coding sessions
CAST_CONTEXT=""
if command -v cast &>/dev/null; then
    CAST_CONTEXT=$(cast diff --today 2>/dev/null | head -100 || echo "")
    if [ -z "$CAST_CONTEXT" ]; then
        CAST_CONTEXT=$(cast feed -s today 2>/dev/null | head -40 || echo "")
    fi
fi

# Call Claude to generate the reminder
PROMPT="It's 9:30 PM. Generate a short, warm shutdown reminder for Jason (a software engineer who tends to keep coding late).

Here's what he worked on today:
${CAST_CONTEXT:-No session data available — just give a generic but warm reminder.}

Requirements:
- One short title (under 50 chars, no quotes)
- One body message (1-2 sentences, warm but direct, referencing his actual work if context is available)
- Return ONLY valid JSON: {\"title\": \"...\", \"body\": \"...\"}
- No markdown, no code fences"

PAYLOAD=$(cat <<EOF
{
    "model": "claude-sonnet-4-5-20241022",
    "temperature": 1,
    "max_tokens": 256,
    "messages": [{"role": "user", "content": $(echo "$PROMPT" | jq -Rs .)}]
}
EOF
)

RESPONSE=$(curl -s --max-time 10 https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$PAYLOAD" 2>/dev/null)

# Extract the text content from Claude's response
TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null)

if [ -n "$TEXT" ]; then
    TITLE=$(echo "$TEXT" | jq -r '.title // empty' 2>/dev/null)
    BODY=$(echo "$TEXT" | jq -r '.body // empty' 2>/dev/null)
fi

# Fallback if anything failed
if [ -z "${TITLE:-}" ]; then TITLE="9:30 PM — time to wind down"; fi
if [ -z "${BODY:-}" ]; then BODY="Nothing good happens after this hour. Sleep beats one more hour of code."; fi

osascript - "$TITLE" "$BODY" <<'APPLESCRIPT'
on run argv
    display notification (item 2 of argv) with title (item 1 of argv) sound name "Default"
end run
APPLESCRIPT
