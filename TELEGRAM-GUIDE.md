# Aurum signals on Telegram (free, laptop can be off)

A small job on GitHub checks gold **every hour** with the same rules as the web app and sends a Telegram message to you (and your brother) for:

- every new **BUY NOW / SELL NOW** signal, with entry, SL, TP, RR, lot size, quality and win chance
- every trade that hits its **stop loss or take profit**
- ⚠️ a warning when big US news is close, and ⛔ when the daily loss limit is reached

It never places trades. Setup takes about 10 minutes.

## 1. Create your bot (Telegram, 3 minutes)

1. In Telegram, search **@BotFather** (blue tick) → **Start** → send `/newbot`.
2. Give it a name (e.g. *Aurum Gold Signals*) and a username ending in `bot` (e.g. `aurum_bunny_bot`).
3. BotFather replies with a **token** like `7123456789:AAH...`. Keep it secret (anyone with it can use your bot).

## 2. Get your chat ID (and your brother's)

1. Open your new bot in Telegram and press **Start** (send any message, e.g. `hi`).
2. Your brother does the same with the same bot.
3. In a browser open (put your token in): `https://api.telegram.org/bot<TOKEN>/getUpdates`
4. Find `"chat":{"id":123456789` — that number is a chat ID. You will see one for each person who messaged the bot.

*A group instead:* add the bot to a group, send a message in the group, and use the group's id from the same page (it starts with `-`).

## 3. Put them in GitHub (secrets stay private)

Repository **Settings → Secrets and variables → Actions**:

**Secrets** tab → **New repository secret**:

| Name | Value |
| --- | --- |
| `TELEGRAM_BOT_TOKEN` | the token from BotFather |
| `TELEGRAM_CHAT_IDS` | the chat IDs, comma separated, e.g. `123456789,987654321` |
| `TWELVE_DATA_KEY` *(optional)* | a free key from twelvedata.com → the bot uses real **XAU/USD** prices instead of PAXG |

**Variables** tab (optional) → **New repository variable**:

| Name | Example | Meaning |
| --- | --- | --- |
| `AURUM_BALANCE` | `1000` | balance for the lot size |
| `AURUM_RISK_PCT` | `1` | risk per trade in % |
| `AURUM_MAX_LOSSES` | `2` | daily loss limit shown in messages (0 = off) |
| `AURUM_TIMEZONE` | `Asia/Kuala_Lumpur` | time zone for times in messages |

## 4. Switch it on and test

1. Open the **Actions** tab. If GitHub asks, click **I understand my workflows, go ahead and enable them**.
2. Click **Aurum Telegram signals** → **Run workflow** → keep *Send a test message* ticked → **Run workflow**.
3. Within a minute you should get **✅ Aurum bot connected** in Telegram, with the trend and any open trade.
4. Also run **Aurum news calendar** once (Actions → Aurum news calendar → Run workflow). It fills the news warnings for the bot and the web app, and then updates itself every 6 hours.

From now on it runs by itself every hour.

## If something goes wrong

- **No message and the run is red:** open the run → click the failed step to read the error.
  - `Telegram refused chat …: chat not found` → that person has not pressed **Start** in the bot, or the ID is wrong.
  - `Unauthorized` → the token is wrong (copy it again from BotFather).
  - `HTTP 451` or `HTTP 403` from Binance → Binance blocks GitHub's US servers. Add the free `TWELVE_DATA_KEY` secret (step 3); then the bot uses XAU/USD from Twelve Data.
- GitHub emails you when a run fails.
- **Messages a few minutes late:** normal. GitHub's hourly timer often starts 5–15 minutes after the hour. For a trade that lasts hours this is fine; the web app (alerts on) is instant.
- **Pause it:** Actions → Aurum Telegram signals → **⋯ → Disable workflow**.

## Good to know

- **Prices:** without a Twelve Data key the messages use PAXG prices, which can differ from your broker by a few dollars. Use the **$ distances** shown (e.g. *SL $9.66 away*) on your broker's chart.
- **Cost:** free. In a private repository each run counts about 1 minute of the 2,000 free minutes a month (≈ 850 minutes a month for both jobs).
- GitHub stops scheduled jobs in repositories with **no activity for 60 days**; the news job's updates keep it active. If it ever stops, Actions shows a button to re-enable it.
