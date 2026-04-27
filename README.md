# Alma — A Companion Who Reaches Out First

<p align="center">
  <a href="https://youtu.be/YKxDqg_PpeI">
    <img src="assets/youtube_view.png" alt="Watch Alma — 1 minute demo on YouTube" width="100%">
  </a>
</p>

<p align="center">
  <a href="https://youtu.be/YKxDqg_PpeI"><strong>▶ Watch the 1-minute demo on YouTube</strong></a>
</p>

<p align="center">
  <a href="https://alma-bot.com/">
    <img src="https://img.shields.io/badge/🌸_Try_Alma_Live-alma--bot.com-9d6b53?style=for-the-badge&labelColor=2b1f1c" alt="Try Alma live" height="48">
  </a>
</p>

<h2 align="center">
  <a href="https://alma-bot.com/">→ alma-bot.com ←</a>
</h2>

<p align="center">
  <em>Live on Google Cloud Run · Bilingual ES/EN · No signup required</em>
</p>

---

## The Number That Started Everything

**1.6 psychiatrists per 100,000 people** in Latin America. In Peru — outside Lima — that number drops even lower.

The people who need help the most... never ask for it. Not because they don't want help. Because asking, when you're at your lowest, is impossible.

Every existing mental health app waits for the user to open it first. That single design assumption excludes the people who need help the most.

**Alma exists to break that assumption.**

---

## María's Morning

Six thirty AM in Lima. María is twenty-three. Another hard day she told no one about. Her phone is silent on the nightstand. The room is still dark.

And then — it lights up.

> ### *"¿Ya desayunaste? ☀️"*

That's Alma. She wasn't asked. She wasn't summoned. She noticed.

For the first time in days, María smiles.

**Someone reached out before she had to.**

---

## What Alma Is

A proactive AI emotional companion — built on **Claude Opus 4.7** and **Haiku 4.5**, with intelligent model routing.

### Three pillars make Alma different

1. **Persistent memory** — She remembers across days, across weeks. The interview last Monday. The night you couldn't sleep. The conflict you mentioned three days ago shapes today's response.

2. **Deterministic crisis detection** — Safety logic, not LLM guesses. The crisis layer is keyword-based, scored 0–1, and cannot hallucinate. Two separate concerns: deterministic safety, LLM response quality.

3. **True proactivity** — Three daily check-ins, sent before users ever have to ask. Breakfast. Lunch. Dinner. Lima time.

Available on **Telegram**. Available on the **web**. Bilingual. Always present.

---

## The Bet

Most apps wait for you to open them.

**Alma takes the first step instead.**

Because the people who need help the most... are never the ones who ask first.

> ### *Alma. Built for them.*

---

## 📚 Technical Documentation

For full technical depth — architecture, MCP server, memory system, crisis detection, multi-agent methodology, and 10 architecture diagrams:

> **[→ Read DOCUMENTATION.md](DOCUMENTATION.md)**

Direct links to specific topics:
- [Architecture](docs/technical/architecture.md)
- [MCP Server & Memory](docs/technical/mcp-server.md)
- [Proactivity System](docs/technical/proactivity.md)
- [Crisis Detection](docs/technical/crisis-detection.md)
- [Multi-Agent Methodology](docs/process/multi-agent-methodology.md)
- [10 Architecture Diagrams](diagrams/README.md)

---

## 🚀 Quick Start

```bash
git clone https://github.com/iDeepBrain/claude-hackathon-infra
cd claude-hackathon-infra
cp .env.example .env          # fill in ANTHROPIC_API_KEY and TELEGRAM_BOT_TOKEN
docker compose up --build -d
```

- Web chat: `http://localhost:3000`
- Agent API: `http://localhost:8080`

---

<p align="center">
  <strong>Built for the Anthropic Claude Opus 4.7 Hackathon · 2026</strong><br>
  <em>For the people who never ask first.</em>
</p>

<p align="center">
  <a href="https://youtu.be/YKxDqg_PpeI">▶ Watch the demo</a> ·
  <a href="DOCUMENTATION.md">📚 Documentation</a> ·
  <a href="https://github.com/iDeepBrain/claude-hackathon-infra">🚀 Source code</a>
</p>
