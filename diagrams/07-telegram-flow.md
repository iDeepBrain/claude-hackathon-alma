# Telegram Reactive Flow

This sequence diagram shows how a user message flows through the Telegram channel. The telegram-bot service runs a polling loop that receives updates from the Telegram API, registers the user's chat_id in Redis (for proactive messaging later), forwards the message to the FastAPI agent via HTTP, collects the SSE stream chunks, concatenates them into a complete response, and sends it back to the user via the Telegram Bot API. The agent runs the same AlmaChain pipeline as the web flow.

```mermaid
sequenceDiagram
    participant USER as 👤 User
    participant TGAPI as Telegram API
    participant BOT as telegram-bot
    participant REDIS as Redis
    participant AGENT as FastAPI Agent
    participant LLM as Anthropic API

    USER->>TGAPI: Send message
    TGAPI-->>BOT: Update (polling)

    BOT->>REDIS: SET alma:chat:{tg_user_id} = chat_id<br/>(first message registration)

    BOT->>AGENT: POST http://agent:8000/api/v1/chat<br/>{user_id: "tg_{tg_user_id}", message, language}

    Note over AGENT: Same AlmaChain pipeline as web

    loop SSE chunks
        AGENT-->>BOT: data: chunk\n\n
        BOT->>BOT: concat chunks
    end
    AGENT-->>BOT: data: [DONE]

    BOT->>TGAPI: sendMessage(chat_id, full_response)
    TGAPI-->>USER: 📱 Alma's reply
```

## Key Takeaways

- **Unified pipeline**: The telegram-bot is a thin client -- it forwards messages to the same `/api/v1/chat` endpoint used by the web frontend, ensuring identical behavior across channels.
- **Chat ID registration enables proactivity**: On the first message, the bot stores `alma:chat:{tg_user_id} = chat_id` in Redis, which APScheduler later reads to send proactive messages directly via the Telegram Bot API.
- **SSE concatenation, not streaming**: Unlike the web flow (which streams tokens to the browser in real-time), the Telegram bot collects all SSE chunks and sends the complete response as a single Telegram message.
