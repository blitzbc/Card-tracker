# Card Tracker

A phone-friendly web app for tracking a sports card collection.

- **Identify cards from a photo.** Snap the front (and optionally the back), and Claude reads the player, year, brand, set, card number, parallel, rookie/auto/relic flags, and, for slabs, the grader, grade and cert number. You can correct anything before saving.
- **Raw and graded values.** Prices come from current eBay listings, sorted into **Raw**, **PSA 10**, **PSA 9**, **BGS 9.5**, **SGC 10** and other grades. Each shows the median, a typical range, and links to the listings.
- **Collection view.** Shows total estimated value, what you paid, gain/loss per card, search and sort, and a price history each time you refresh.

## Setup

Requires Node.js 20+.

```bash
cd card-tracker
npm install
cp .env.example .env.local   # then fill in the keys below
npm run dev                  # http://localhost:3000
```

### API keys

| Key | What it's for | Where to get it |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | Identifying cards from photos | [console.anthropic.com](https://console.anthropic.com/) → API keys |
| `EBAY_CLIENT_ID` / `EBAY_CLIENT_SECRET` | Price lookups | [developer.ebay.com](https://developer.ebay.com/my/keys): create an app and use the **Production** keyset (App ID = client ID, Cert ID = client secret) |

For development, put the keys in `.env.local`. For the Windows setup below, the installer asks for them instead. The app runs without the keys, but identification and pricing stay off until you add them. A banner says which keys are missing. You can always enter card details and your own value by hand.

## Run it on a Windows PC and use it from your phone

The app runs on a Windows PC that stays on. Your phone opens it in the browser, on home Wi-Fi or from anywhere through Tailscale. The collection is backed up to OneDrive automatically.

### Install

1. Get the code onto the PC: either `git clone https://github.com/blitzbc/card-tracker` (recommended, makes updating easy) or *Code -> Download ZIP* on GitHub and unzip it somewhere permanent, e.g. `Documents\card-tracker`.
2. Double-click **`install.cmd`** in that folder. It will:
   - install Node.js with winget if it's missing (then ask you to run `install.cmd` again),
   - ask for a **password** for the app, your **Anthropic API key**, your **eBay keys**, and the **OneDrive folder** for backups (defaults to `OneDrive\CardTracker`),
   - build the app and set it to start in the background whenever you log in to Windows,
   - ask Windows for permission to open port 3000 to your home network and Tailscale only,
   - print the addresses to open on your phone.

Keys and the password are saved in `%LOCALAPPDATA%\CardTracker\config.json`, encrypted so that only your Windows account on this PC can read them. To change them, run `install.cmd` again and press Enter for anything you want to keep.

### Open it on your phone

- **At home:** connect the phone to the same Wi-Fi and open the "Phone on home Wi-Fi" address the installer printed, e.g. `http://192.168.1.20:3000`.
- **Anywhere:** install [Tailscale](https://tailscale.com/download) on the PC and on your phone and sign in to the same account on both. Then open `http://<pc-name>:3000` (or the `100.x.x.x` address) on the phone. Only your own devices can reach it.
- **Add it to your home screen:** in Safari, Share -> *Add to Home Screen*; in Chrome on Android, the menu -> *Add to Home screen*.

### Keep the PC reachable

The app runs while you're logged in to Windows. Locking the screen is fine, but sleep and signing out stop it. To keep it reachable, set *Settings -> System -> Power -> Screen and sleep -> When plugged in, put my device to sleep after* to **Never**.

### Your data and the OneDrive backup

- The live collection is in `%LOCALAPPDATA%\CardTracker\data` on the PC's own disk. OneDrive uploads files while they're being written, which can corrupt a live database, so the database itself stays out of OneDrive.
- About 10 seconds after any change, the app writes a clean copy (`cards.db` plus an `images` folder) to your OneDrive backup folder. If a backup fails, a warning appears at the top of the app.
- **Moving to a new PC or reinstalling:** let OneDrive finish syncing on the new PC, then run `install.cmd` and give it the same backup folder. When no local collection exists, the app restores it from the backup on first start.

### Update, stop, uninstall

- **Update to the latest version:** double-click `update.cmd`. It pulls the code, rebuilds, and restarts.
- **Stop or start by hand:** open Task Scheduler and find the **Card Tracker** task.
- **Logs:** `%LOCALAPPDATA%\CardTracker\server.log` and `server-error.log`.
- **Uninstall:** `uninstall.cmd` removes the startup task and firewall rule. Your data and backup stay where they are.

## How pricing works

For each card the app runs two eBay Browse API searches in *Sports Trading Card Singles*: the card's search query, and the same query biased toward slabbed copies. Then it:

1. Drops lots, reprints and "you pick" listings. It also drops autographed, numbered and relic versions unless your card is one of those, so a base card isn't priced against its rare parallels.
2. Reads the grader and grade from each title ("PSA 10 GEM MINT", "Beckett 9.5", etc.). Titles like "PSA 10 candidate" or "PSA ready" count as raw.
3. Groups listings into Raw and per-grade buckets, removes outliers, and reports the median and the middle-50% range.

**Your card's value** is the bucket that matches it: Raw for a raw card, or for example PSA 9 if you own a PSA 9. Set **Own value** on a card to override it.

**Caveat:** these are *asking* prices on active listings, not completed sales, and asking prices usually run higher. eBay's sold-price API is limited to approved partners. Each price panel therefore links to eBay's sold-listings search for that card, so you can check real sales. The **eBay search used for prices** field on each card controls the query. If prices look off (for example, the base card mixed with a parallel), tighten or simplify it and tap *Refresh prices*.

## Project layout

```
src/
  app/
    page.tsx               collection list + totals
    add/page.tsx           photo → identify → review → price → save
    cards/[id]/page.tsx    card detail, prices, history, edit
    api/
      identify/            POST photo(s) → card details (Claude)
      prices/              POST card details → price report (eBay), used before saving
      cards/               list / create
      cards/[id]/          get / update / delete
      cards/[id]/prices    refresh prices and record history
      cards/[id]/image     stored card photo
  lib/
    identify.ts            Claude vision call with a structured-output schema
    ebay.ts                eBay OAuth + Browse API search
    pricing.ts             title parsing, raw/graded buckets, stats (unit-tested)
    db.ts                  SQLite schema and queries (data/cards.db)
    backup.ts              snapshot to BACKUP_DIR (OneDrive) after changes; restore on first start
    session.ts             optional password login (APP_PASSWORD)
  middleware.ts            sends signed-out visitors to /login
scripts/windows/           install / start / update / uninstall for running on a Windows PC
```

Data (the database and card photos) lives in `./data/`, or in `DATA_DIR` if set. It's git-ignored. Set `BACKUP_DIR` to keep an automatic copy elsewhere.

## Scripts

- `npm run dev`: development server
- `npm run build && npm start`: production
- `npm test`: unit tests for the pricing logic
- `npm run lint`: lint
