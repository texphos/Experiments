# Duty Packet

A grant-packet desk for small U.S. police departments (typically 24 or fewer sworn officers). Agency profile in, fileable packet out. **Packet and checklist only.** Duty Packet does not submit to Grants.gov or JustGrants.

This is the existing Duty Packet project (`server.py`, `index.html`, `Start-DutyPacket.bat`). Work here. Do not start a second folder.

## Near-term output

- A **state** JAG pass-through packet for the named state. Direct federal JAG Local formula awards die under about $10,000. The app names that state's State Administering Agency and will not invent a universal JAG PDF.
- An **FY27 COPS Hiring readiness sheet**. It is not an FY26 CHP application (that window is closed). The app hardcodes no deadlines and does not scrape COPS. Live windows are owned outside the app.

## Sourced numbers only

- Population comes from Census **ACS 5-year** estimates for that town (Census place, or a matching county subdivision in New England). Never ACS 1-year. Never a county number on the town.
- Crime comes from **FBI CDE for that ORI only**. If CDE has no row, the field stays blank.
- Census ACS and FBI CDE **fail closed without API keys**. No statistic is invented. CrimeGrade, City-Data, Wikipedia, and nearby cities are not used.
- Every number in the packet needs a year and a source.

CHP readiness: the 25% match (or waiver) and the 12-month post-grant retention stay blank until the chief answers.

## Run on Windows

1. Copy `.env.example` to `.env`.
2. Add a [Census API key](https://api.census.gov/data/key_signup.html) and an [api.data.gov key](https://api.data.gov/signup/) for FBI CDE.
3. Double-click `Start-DutyPacket.bat`.

The desk opens at `http://127.0.0.1:8765`.

## Run elsewhere

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # then add keys
python server.py
```

## Packet files

PDFs are written to `packets/` with **agency + grant + date** in the filename so last year's packet is not overwritten.

Incomplete packets print with an incomplete banner and list every blank the chief or mayor still owes. They are not styled as finished filings.

## What this is not

No CAD/RMS, warrant feeds, court APIs, or surveillance. Legitimate grant-writing only.
