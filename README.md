# Duty Packet

A grant-packet desk for small U.S. police departments (typically 24 or fewer sworn officers). Agency profile in, fileable packet out. **Packet and checklist only.** Duty Packet does not submit to eGrants, Grants.gov, or JustGrants.

This is the existing Duty Packet project (`server.py`, `index.html`, `Start-DutyPacket.bat`). Work here. Do not start a second folder or a new repo.

## Named state: Texas

Near-term output is a **Texas Criminal Justice Grant Program** desk packet.

- SAA: Office of the Governor, Public Safety Office
- File in **eGrants**: https://egrants.gov.texas.gov/
- eGrants **is** the form. This app does not invent a Texas JAG PDF.
- The FY2027 cycle closed 12 February 2026 at 5:00 PM CST. That window is dead. The next cycle is not posted. Historically December open / February certify. Watch eGrants.
- Do not scrape COPS. Do not hardcode other live windows.

Rules that kill a Texas packet if skipped:

- Apply as the **city**, not the police department.
- Hit the regional Council of Governments first (all 24 run their own workshop and priority list). PSO will bounce a skip.
- County filings need 90%+ CCH disposition completeness at DPS.
- Upload the CEO/Law Enforcement Certifications form in eGrants.
- County Essential Services is invitation-only to counties, not municipal PDs — ignore it.

Also produced: an **FY27 COPS Hiring readiness sheet**. Not an FY26 CHP application.

## Sourced numbers only

- Population comes from Census **ACS 5-year** estimates for that town (Census place). Never ACS 1-year. Never a county number on the town.
- Crime comes from **FBI CDE for that ORI only**. If CDE has no row, the field stays blank.
- Census ACS and FBI CDE **fail closed without API keys**. No statistic is invented.

CHP readiness: the 25% match (or waiver) and the 12-month post-grant retention stay blank until the chief answers. Narrative frames stay bracketed. No sample town.

## Print

City-hall packet: cream `#F7F1E6`, ink `#1B2430`, Georgia / EB Garamond, 1-inch margins, 0.7-inch empty ring seal, footer `agency · grant · date · page`. Required blanks stamp **DRAFT** and list who owes them. Signature lines for the chief and the mayor.

## Run on Windows

1. Copy `.env.example` to `.env`.
2. Add a Census API key and an api.data.gov key for FBI CDE.
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

PDFs go to `packets/` with city, grant, and date in the filename.

## What this is not

No CAD/RMS, warrant feeds, court APIs, or surveillance. Legitimate grant-writing only.
