#!/usr/bin/env bash

jira_default_issue_fields() {
  printf '%s\n' 'summary,description,status,issuetype,assignee,reporter,labels,priority,components,parent,subtasks,comment'
}

jira_base_url() {
  local base="${JIRA_BASE_URL:-${JIRA_URL:-}}"
  base="${base%/}"
  printf '%s\n' "$base"
}

jira_api_version() {
  printf '%s\n' "${JIRA_API_VERSION:-3}"
}

jira_auth_mode() {
  if [ -n "${JIRA_AUTH_MODE:-}" ]; then
    printf '%s\n' "$JIRA_AUTH_MODE"
    return 0
  fi

  if [ -n "${JIRA_USER:-}" ] && [ -n "${JIRA_TOKEN:-}" ]; then
    printf '%s\n' 'basic'
    return 0
  fi

  if [ -n "${JIRA_TOKEN:-}" ]; then
    printf '%s\n' 'bearer'
    return 0
  fi

  printf '%s\n' 'none'
}

jira_is_configured() {
  [ -n "$(jira_base_url)" ] && [ "$(jira_auth_mode)" != 'none' ]
}

jira_is_ticket_key() {
  [[ "$1" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]]
}

jira_require_config() {
  local base auth
  base="$(jira_base_url)"
  auth="$(jira_auth_mode)"

  if [ -z "$base" ]; then
    echo 'JIRA_BASE_URL (or JIRA_URL) is required.' >&2
    return 1
  fi

  case "$auth" in
    basic)
      if [ -z "${JIRA_USER:-}" ] || [ -z "${JIRA_TOKEN:-}" ]; then
        echo 'JIRA_USER and JIRA_TOKEN are required for basic auth.' >&2
        return 1
      fi
      ;;
    bearer)
      if [ -z "${JIRA_TOKEN:-}" ]; then
        echo 'JIRA_TOKEN is required for bearer auth.' >&2
        return 1
      fi
      ;;
    *)
      echo 'Set JIRA_USER/JIRA_TOKEN (basic) or JIRA_TOKEN + JIRA_AUTH_MODE=bearer.' >&2
      return 1
      ;;
  esac
}

jira_fetch_issue_json() {
  local issue_key="${1:-}"
  local fields="${2:-$(jira_default_issue_fields)}"
  local base auth url

  if ! jira_is_ticket_key "$issue_key"; then
    echo "Invalid Jira issue key: $issue_key" >&2
    return 1
  fi

  jira_require_config || return 1

  base="$(jira_base_url)"
  auth="$(jira_auth_mode)"
  url="${base}/rest/api/$(jira_api_version)/issue/${issue_key}?fields=${fields}"

  case "$auth" in
    basic)
      curl -fsS \
        -u "$JIRA_USER:$JIRA_TOKEN" \
        -H 'Accept: application/json' \
        -H 'Content-Type: application/json' \
        "$url"
      ;;
    bearer)
      curl -fsS \
        -H "Authorization: Bearer $JIRA_TOKEN" \
        -H 'Accept: application/json' \
        -H 'Content-Type: application/json' \
        "$url"
      ;;
    *)
      echo 'Unsupported Jira auth mode.' >&2
      return 1
      ;;
  esac
}

jira_render_issue_markdown() {
  python3 -c '
import json
import sys


def adf_to_text(node, indent=""):
    if node is None:
        return ""
    if isinstance(node, str):
        return node
    if isinstance(node, list):
        return "".join(adf_to_text(item, indent) for item in node)
    if not isinstance(node, dict):
        return str(node)

    text = node.get("text")
    if text is not None:
        return text

    node_type = node.get("type", "")
    content = node.get("content", [])

    if node_type in {"doc", "blockquote", "panel"}:
        return "".join(adf_to_text(item, indent) for item in content)
    if node_type in {"paragraph", "heading"}:
        body = "".join(adf_to_text(item, indent) for item in content).strip()
        return (body + "\n\n") if body else ""
    if node_type == "hardBreak":
        return "\n"
    if node_type == "bulletList":
        return "".join(adf_to_text(item, indent) for item in content)
    if node_type == "orderedList":
        lines = []
        for index, item in enumerate(content, start=1):
            rendered = adf_to_text(item, f"{indent}{index}. ").rstrip()
            if rendered:
                lines.append(rendered + "\n")
        return "".join(lines) + ("\n" if lines else "")
    if node_type == "listItem":
        body = "".join(adf_to_text(item, indent + "  ") for item in content).strip()
        if not body:
            return ""
        prefix = indent or "- "
        body = body.replace("\n", "\n" + " " * len(prefix))
        return f"{prefix}{body}\n"
    if node_type == "codeBlock":
        body = "".join(adf_to_text(item, indent) for item in content).rstrip()
        return f"```\n{body}\n```\n\n" if body else ""

    return "".join(adf_to_text(item, indent) for item in content)


def field_name(value, nested=None):
    if not value:
        return "[unknown]"
    if nested:
        value = value.get(nested)
    if isinstance(value, dict):
        return value.get("displayName") or value.get("name") or value.get("value") or "[unknown]"
    return str(value)


def render_description(value):
    if not value:
        return "[no description]"
    if isinstance(value, str):
        return value.strip() or "[no description]"
    if isinstance(value, dict):
        rendered = adf_to_text(value).strip()
        return rendered or "[no description]"
    return str(value)


def render_comments(comments):
    if not comments:
        return "- none"
    lines = []
    for item in comments[:5]:
        author = field_name(item.get("author"))
        body = render_description(item.get("body")).replace("\n", " ").strip()
        body = body if len(body) <= 220 else body[:217] + "..."
        lines.append(f"- {author}: {body}")
    return "\n".join(lines)


data = json.load(sys.stdin)
fields = data.get("fields", {})
summary = fields.get("summary") or "[no summary]"
status = field_name(fields.get("status"))
issue_type = field_name(fields.get("issuetype"))
assignee = field_name(fields.get("assignee"))
reporter = field_name(fields.get("reporter"))
priority = field_name(fields.get("priority"))
labels = ", ".join(fields.get("labels") or []) or "none"
components = ", ".join(c.get("name", "") for c in fields.get("components") or [] if c.get("name")) or "none"
parent = field_name(fields.get("parent"), "key") if fields.get("parent") else "none"
subtasks = ", ".join(item.get("key", "") for item in fields.get("subtasks") or [] if item.get("key")) or "none"
description = render_description(fields.get("description"))
comments = render_comments((fields.get("comment") or {}).get("comments") or [])

output = f"""# {data.get("key", "[unknown]")} — {summary}

## Metadata
- Status: {status}
- Type: {issue_type}
- Assignee: {assignee}
- Reporter: {reporter}
- Priority: {priority}
- Labels: {labels}
- Components: {components}
- Parent: {parent}
- Subtasks: {subtasks}

## Description
{description}

## Recent Comments
{comments}
"""

sys.stdout.write(output.rstrip() + "\n")
'
}

jira_write_issue_markdown() {
  local issue_key="${1:-}"
  local output_file="${2:-}"
  local fields="${3:-$(jira_default_issue_fields)}"

  if [ -z "$output_file" ]; then
    echo 'Output file path is required.' >&2
    return 1
  fi

  jira_fetch_issue_json "$issue_key" "$fields" | jira_render_issue_markdown > "$output_file"
}

jira_fetch_summary() {
  local issue_key="${1:-}"
  local json

  if ! jira_is_ticket_key "$issue_key"; then
    return 1
  fi
  if ! jira_is_configured; then
    return 1
  fi

  json="$(jira_fetch_issue_json "$issue_key" "summary" 2>/dev/null)" || return 1

  printf '%s' "$json" | python3 -c '
import json
import re
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
summary = (data.get("fields") or {}).get("summary") or ""
cleaned = re.sub(r"^\[[^\]]+\]\s*", "", summary).strip()
if not cleaned:
    sys.exit(1)
print(cleaned)
'
}

