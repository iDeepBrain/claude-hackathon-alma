#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
WARN=0

pass() { ((PASS++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); echo "  ❌ $1"; }
warn() { ((WARN++)); echo "  ⚠️  $1"; }

echo "========================================"
echo " Alma Documentation Validation Suite"
echo "========================================"
echo ""

# ─────────────────────────────────────────────
# TEST 1: File Structure Integrity
# ─────────────────────────────────────────────
echo "── TEST 1: File Structure ──"

REQUIRED_FILES=(
  "README.md"
  "CLAUDE.md"
  "LICENSE"
  "docs/technical/architecture.md"
  "docs/technical/mcp-server.md"
  "docs/technical/memory-system.md"
  "docs/technical/crisis-detection.md"
  "docs/technical/proactivity.md"
  "docs/user/getting-started.md"
  "docs/user/privacy.md"
  "docs/process/multi-agent-methodology.md"
  "docs/process/claude-code-skills.md"
  "diagrams/README.md"
  "diagrams/01-global-architecture.md"
  "diagrams/02-inter-service-map.md"
  "diagrams/03-agent-internals.md"
  "diagrams/04-mcp-memory.md"
  "diagrams/05-proactivity-flow.md"
  "diagrams/06-web-chat-flow.md"
  "diagrams/07-telegram-flow.md"
  "diagrams/08-docker-network.md"
  "diagrams/09-data-flows.md"
  "diagrams/10-connection-params.md"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [ -f "$f" ]; then
    lines=$(wc -l < "$f")
    if [ "$lines" -gt 5 ]; then
      pass "$f exists ($lines lines)"
    else
      fail "$f exists but too short ($lines lines)"
    fi
  else
    fail "$f MISSING"
  fi
done

echo ""

# ─────────────────────────────────────────────
# TEST 2: No Placeholder URLs
# ─────────────────────────────────────────────
echo "── TEST 2: No Placeholder URLs ──"

placeholders=$(grep -rn "github.com/user/\|github.com/your-org/\|github.com/YOUR\|github.com/example" --include="*.md" . 2>/dev/null || true)
if [ -z "$placeholders" ]; then
  pass "No placeholder GitHub URLs found"
else
  fail "Placeholder URLs found:"
  echo "$placeholders" | while read -r line; do echo "       $line"; done
fi

idb_count=$(grep -c "github.com/iDeepBrain/" README.md 2>/dev/null || echo "0")
if [ "$idb_count" -ge 8 ]; then
  pass "README.md has $idb_count iDeepBrain URLs (expected ≥8)"
else
  fail "README.md has only $idb_count iDeepBrain URLs (expected ≥8)"
fi

echo ""

# ─────────────────────────────────────────────
# TEST 3: Internal Link Validation
# ─────────────────────────────────────────────
echo "── TEST 3: Internal Links (README.md) ──"

broken_count=0
while IFS= read -r link; do
  if [ -n "$link" ] && [ ! -f "$link" ]; then
    fail "Broken link: $link"
    ((broken_count++))
  elif [ -n "$link" ]; then
    pass "Link OK: $link"
  fi
done < <(grep -oP '\]\((?!http)(.*?)\)' README.md 2>/dev/null | tr -d '()' | sed 's/\]//g' || true)

if [ "$broken_count" -eq 0 ]; then
  pass "All README.md internal links valid"
fi

echo ""
echo "── TEST 3b: Internal Links (diagrams/README.md) ──"

cd diagrams
broken_count=0
while IFS= read -r link; do
  if [ -n "$link" ] && [ ! -f "$link" ]; then
    fail "Broken link in diagrams/README.md: $link"
    ((broken_count++))
  elif [ -n "$link" ]; then
    pass "Link OK: $link"
  fi
done < <(grep -oP '\]\((?!http)(.*?)\)' README.md 2>/dev/null | tr -d '()' | sed 's/\]//g' || true)

if [ "$broken_count" -eq 0 ]; then
  pass "All diagrams/README.md internal links valid"
fi
cd "$REPO_ROOT"

echo ""

# ─────────────────────────────────────────────
# TEST 4: Redis Key Consistency
# ─────────────────────────────────────────────
echo "── TEST 4: Redis Key Consistency ──"

canonical_crisis_key="alma:proactive:crisis_score"
canonical_last_key="alma:proactive:last"

bad_crisis=$(grep -rn "alma:crisis:last" --include="*.md" . 2>/dev/null || true)
if [ -z "$bad_crisis" ]; then
  pass "No legacy 'alma:crisis:last' keys found"
else
  fail "Legacy 'alma:crisis:last' found (should be '$canonical_crisis_key'):"
  echo "$bad_crisis" | while read -r line; do echo "       $line"; done
fi

bad_session=$(grep -rn "alma:session:last_activity" --include="*.md" . 2>/dev/null || true)
if [ -z "$bad_session" ]; then
  pass "No legacy 'alma:session:last_activity' keys found"
else
  fail "Legacy 'alma:session:last_activity' found (should be '$canonical_last_key'):"
  echo "$bad_session" | while read -r line; do echo "       $line"; done
fi

last_sent=$(grep -rn "alma:proactive:last_sent" --include="*.md" . 2>/dev/null || true)
if [ -z "$last_sent" ]; then
  pass "No divergent 'alma:proactive:last_sent' keys (canonical: 'alma:proactive:last')"
else
  fail "Divergent 'alma:proactive:last_sent' found (should be '$canonical_last_key'):"
  echo "$last_sent" | while read -r line; do echo "       $line"; done
fi

echo ""

# ─────────────────────────────────────────────
# TEST 5: Model Name Consistency
# ─────────────────────────────────────────────
echo "── TEST 5: Model Name Consistency ──"

valid_models=("claude-opus-4-7" "claude-sonnet-4-6" "claude-haiku-4-5" "all-MiniLM-L6-v2")

old_models=$(grep -rn "claude-sonnet-4-5\|claude-haiku-4-4\|claude-3\|claude-opus-4-6\|gpt-" --include="*.md" . 2>/dev/null || true)
if [ -z "$old_models" ]; then
  pass "No outdated or wrong model names found"
else
  fail "Outdated/wrong model names found:"
  echo "$old_models" | while read -r line; do echo "       $line"; done
fi

for model in "${valid_models[@]}"; do
  count=$(grep -rc "$model" --include="*.md" . 2>/dev/null | awk -F: '{s+=$2}END{print s}')
  if [ "$count" -gt 0 ]; then
    pass "$model referenced $count times"
  else
    warn "$model not referenced anywhere"
  fi
done

echo ""

# ─────────────────────────────────────────────
# TEST 6: Threshold Consistency
# ─────────────────────────────────────────────
echo "── TEST 6: Threshold Consistency ──"

crisis_gate_06=$(grep -rn "0\.6" docs/technical/architecture.md docs/technical/proactivity.md docs/technical/crisis-detection.md 2>/dev/null | grep -i "crisis\|gate\|suppress\|skip" || true)
if [ -n "$crisis_gate_06" ]; then
  pass "Crisis gate threshold 0.6 consistent across technical docs"
else
  fail "Crisis gate threshold 0.6 not found consistently"
fi

crisis_routing_07=$(grep -n "0\.7.*opus\|opus.*0\.7" docs/technical/architecture.md 2>/dev/null || true)
if [ -n "$crisis_routing_07" ]; then
  pass "Crisis routing threshold 0.7 → Opus in architecture.md"
else
  fail "Crisis routing threshold 0.7 → Opus missing in architecture.md"
fi

cache_092=$(grep -rn "0\.92" docs/technical/architecture.md 2>/dev/null || true)
if [ -n "$cache_092" ]; then
  pass "Semantic cache threshold 0.92 in architecture.md"
else
  fail "Semantic cache threshold 0.92 missing"
fi

echo ""

# ─────────────────────────────────────────────
# TEST 7: Schedule Times Consistency
# ─────────────────────────────────────────────
echo "── TEST 7: Schedule Times ──"

for time in "08:30\|hour=8.*minute=30" "13:30\|hour=13.*minute=30" "19:30\|hour=19.*minute=30"; do
  slot_name=$(echo "$time" | sed 's/\\|.*//')
  arch_hit=$(grep -c "$time" docs/technical/architecture.md 2>/dev/null || echo "0")
  proact_hit=$(grep -c "$time" docs/technical/proactivity.md 2>/dev/null || echo "0")
  if [ "$arch_hit" -gt 0 ] && [ "$proact_hit" -gt 0 ]; then
    pass "Schedule time pattern present in both architecture.md and proactivity.md"
  else
    fail "Schedule time inconsistency: arch=$arch_hit, proactivity=$proact_hit"
  fi
done

lima_tz=$(grep -rc "America/Lima" docs/technical/architecture.md docs/technical/proactivity.md 2>/dev/null | awk -F: '{s+=$2}END{print s}')
if [ "$lima_tz" -ge 2 ]; then
  pass "America/Lima timezone referenced $lima_tz times in technical docs"
else
  fail "America/Lima timezone underreferenced ($lima_tz times)"
fi

echo ""

# ─────────────────────────────────────────────
# TEST 8: Port Consistency
# ─────────────────────────────────────────────
echo "── TEST 8: Port Numbers ──"

for port_pattern in "3000" "8080" "8000" "8001" "6379"; do
  count=$(grep -rc "$port_pattern" --include="*.md" . 2>/dev/null | awk -F: '{s+=$2}END{print s}')
  if [ "$count" -gt 0 ]; then
    pass "Port $port_pattern referenced $count times"
  else
    warn "Port $port_pattern not found"
  fi
done

echo ""

# ─────────────────────────────────────────────
# TEST 9: Mermaid Diagrams Syntax
# ─────────────────────────────────────────────
echo "── TEST 9: Mermaid Diagrams ──"

for diagram in diagrams/[0-9]*.md; do
  name=$(basename "$diagram")
  has_open=$(grep -c '```mermaid' "$diagram" 2>/dev/null || echo "0")
  has_close=$(grep -c '```$' "$diagram" 2>/dev/null || echo "0")
  if [ "$has_open" -gt 0 ] && [ "$has_close" -ge "$has_open" ]; then
    pass "$name: mermaid block well-formed ($has_open blocks)"
  else
    fail "$name: mermaid block malformed (open=$has_open, close=$has_close)"
  fi
done

echo ""

# ─────────────────────────────────────────────
# TEST 10: MCP Tool Names Consistency
# ─────────────────────────────────────────────
echo "── TEST 10: MCP Tool Names ──"

CANONICAL_TOOLS=("get_memory_tool" "search_memories_tool" "upsert_memory_tool" "build_context_tool" "evaluate_crisis_risk_tool")

for tool in "${CANONICAL_TOOLS[@]}"; do
  mcp_hit=$(grep -c "$tool" docs/technical/mcp-server.md 2>/dev/null || echo "0")
  if [ "$mcp_hit" -gt 0 ]; then
    pass "$tool in mcp-server.md ($mcp_hit refs)"
  else
    fail "$tool MISSING from mcp-server.md"
  fi
done

echo ""

# ─────────────────────────────────────────────
# TEST 11: No Sensitive Data Leaked
# ─────────────────────────────────────────────
echo "── TEST 11: No Secrets ──"

secrets=$(grep -rn "sk-ant-\|TELEGRAM_BOT_TOKEN=.\{10,\}\|password=.\{3,\}\|secret=.\{3,\}" --include="*.md" . 2>/dev/null | grep -v "example\|placeholder\|\.env\.\|fill in\|Required\|\.\.\." || true)
if [ -z "$secrets" ]; then
  pass "No hardcoded secrets found"
else
  fail "Possible secrets found:"
  echo "$secrets" | while read -r line; do echo "       $line"; done
fi

echo ""

# ─────────────────────────────────────────────
# TEST 12: Service Names in README match architecture
# ─────────────────────────────────────────────
echo "── TEST 12: Service Names ──"

SERVICES=("agent" "mcp" "web" "telegram-bot" "redis")
for svc in "${SERVICES[@]}"; do
  readme_hit=$(grep -c "$svc" README.md 2>/dev/null || echo "0")
  arch_hit=$(grep -c "$svc" docs/technical/architecture.md 2>/dev/null || echo "0")
  if [ "$readme_hit" -gt 0 ] && [ "$arch_hit" -gt 0 ]; then
    pass "Service '$svc' in both README ($readme_hit) and architecture ($arch_hit)"
  else
    fail "Service '$svc': README=$readme_hit, architecture=$arch_hit"
  fi
done

echo ""

# ─────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────
echo "========================================"
echo " RESULTS: $PASS passed, $FAIL failed, $WARN warnings"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  exit 0
fi
