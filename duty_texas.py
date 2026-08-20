"""Texas Criminal Justice Grant Program routing. eGrants is the form."""

from __future__ import annotations

from typing import Any

NAMED_STATE = "TX"
NAMED_STATE_NAME = "Texas"
SAA_NAME = "Office of the Governor, Public Safety Office"
PROGRAM_NAME = "Criminal Justice Grant Program"
EGRANTS_URL = "https://egrants.gov.texas.gov/"
SAA_URL = "https://gov.texas.gov/organization/public-safety"

# Closed cycle only. Not a live window. Next cycle is not posted.
FY2027_WINDOW_NOTE = (
    "The FY2027 Criminal Justice Grant Program cycle closed 12 February 2026 "
    "at 5:00 PM CST. That window is dead. The next cycle is not posted. "
    "Historically the notice opens in December and certifications run in "
    "February. Watch eGrants. This desk does not scrape eGrants or COPS."
)

FORM_WARNING = (
    "eGrants is the form. Duty Packet is desk prep and a checklist only. "
    "This file is not a Texas JAG PDF, not a Criminal Justice Grant Program "
    "application, and not a substitute for eGrants."
)

COUNTY_ESSENTIAL_NOTE = (
    "County Essential Services (through 31 August) is invitation-only to "
    "counties, not municipal police departments. Ignore it."
)

DIRECT_FLOOR_NOTE = (
    "Direct federal JAG Local formula awards end when the calculated "
    "allocation is under about $10,000. A Texas city of this size files a "
    "Criminal Justice Grant Program request in eGrants after its regional "
    "Council of Governments, not a direct federal JAG application."
)

# All 24 Texas regional councils. Each runs its own workshop and priority list.
TEXAS_COGS: list[dict[str, str]] = [
    {"id": "AACOG", "name": "Alamo Area Council of Governments"},
    {"id": "ARK-TEX", "name": "Ark-Tex Council of Governments"},
    {"id": "BVCOG", "name": "Brazos Valley Council of Governments"},
    {"id": "CAPCOG", "name": "Capital Area Council of Governments"},
    {"id": "CTCOG", "name": "Central Texas Council of Governments"},
    {"id": "CBCOG", "name": "Coastal Bend Council of Governments"},
    {"id": "CVCOG", "name": "Concho Valley Council of Governments"},
    {"id": "DETCOG", "name": "Deep East Texas Council of Governments"},
    {"id": "ETCOG", "name": "East Texas Council of Governments"},
    {"id": "GCRPC", "name": "Golden Crescent Regional Planning Commission"},
    {"id": "HOTCOG", "name": "Heart of Texas Council of Governments"},
    {"id": "HGAC", "name": "Houston-Galveston Area Council"},
    {"id": "LRGVDC", "name": "Lower Rio Grande Valley Development Council"},
    {"id": "MRGDC", "name": "Middle Rio Grande Development Council"},
    {"id": "NORTEX", "name": "Nortex Regional Planning Commission"},
    {"id": "NCTCOG", "name": "North Central Texas Council of Governments"},
    {"id": "PRPC", "name": "Panhandle Regional Planning Commission"},
    {"id": "PBRPC", "name": "Permian Basin Regional Planning Commission"},
    {"id": "RGCOG", "name": "Rio Grande Council of Governments"},
    {"id": "SETRPC", "name": "South East Texas Regional Planning Commission"},
    {"id": "SPAG", "name": "South Plains Association of Governments"},
    {"id": "STDC", "name": "South Texas Development Council"},
    {"id": "TCOG", "name": "Texoma Council of Governments"},
    {"id": "WCTCOG", "name": "West Central Texas Council of Governments"},
]

COG_IDS = frozenset(row["id"] for row in TEXAS_COGS)


def cog_label(cog_id: str) -> str:
    for row in TEXAS_COGS:
        if row["id"] == cog_id:
            return f"{row['name']} ({row['id']})"
    return ""


def applicant_type(profile: dict[str, Any]) -> str:
    raw = str(profile.get("applicant_type") or "").strip().lower()
    if raw in {"city", "municipality", "town"}:
        return "city"
    if raw in {"county"}:
        return "county"
    if raw in {"pd", "police", "police department", "department"}:
        return "pd"
    return raw


def texas_saa_block() -> dict[str, Any]:
    return {
        "ok": True,
        "state_abbr": NAMED_STATE,
        "state": NAMED_STATE_NAME,
        "saa": SAA_NAME,
        "url": SAA_URL,
        "portal": "eGrants",
        "portal_url": EGRANTS_URL,
        "program": PROGRAM_NAME,
        "direct_floor_note": DIRECT_FLOOR_NOTE,
        "form_warning": FORM_WARNING,
        "window_note": FY2027_WINDOW_NOTE,
        "county_essential_note": COUNTY_ESSENTIAL_NOTE,
        "named_state": True,
    }


def texas_kills(profile: dict[str, Any]) -> list[dict[str, str]]:
    """Rules that kill a Texas packet if skipped."""
    kills: list[dict[str, str]] = []
    kind = applicant_type(profile)
    city = str(profile.get("city_name") or "").strip()
    cog = str(profile.get("cog") or "").strip()
    if kind == "pd":
        kills.append(
            {
                "who": "mayor",
                "item": "Apply as the CITY, not the police department. PSO will not take a PD applicant.",
                "rule": "city_applicant",
            }
        )
    elif kind == "county":
        kills.append(
            {
                "who": "mayor",
                "item": "This desk is for a city applicant. A county filing is a different path.",
                "rule": "city_applicant",
            }
        )
    elif kind != "city":
        kills.append(
            {
                "who": "mayor",
                "item": "Name the CITY as the legal applicant. Do not apply as the PD.",
                "rule": "city_applicant",
            }
        )
    elif not city:
        kills.append(
            {
                "who": "mayor",
                "item": "City legal name (the applicant in eGrants is the city, not the PD)",
                "rule": "city_applicant",
            }
        )
    if cog not in COG_IDS:
        kills.append(
            {
                "who": "chief",
                "item": "Regional Council of Governments — go to the COG workshop and priority list first. PSO will bounce a skip.",
                "rule": "cog_required",
            }
        )
    elif not profile.get("cog_first"):
        kills.append(
            {
                "who": "chief",
                "item": "Confirm the COG workshop / priority list was hit before eGrants. PSO will bounce a skip.",
                "rule": "cog_required",
            }
        )
    if kind == "county" and not profile.get("cch_90"):
        kills.append(
            {
                "who": "mayor",
                "item": "County filings need 90%+ CCH disposition completeness at DPS.",
                "rule": "cch_90",
            }
        )
    if not profile.get("ceo_le_certifications"):
        kills.append(
            {
                "who": "mayor",
                "item": "Upload the CEO/Law Enforcement Certifications form in eGrants.",
                "rule": "ceo_le_certifications",
            }
        )
    if not profile.get("egrants_is_the_form"):
        kills.append(
            {
                "who": "chief",
                "item": "Acknowledge that eGrants is the form. This desk does not invent a Texas JAG PDF.",
                "rule": "egrants_is_the_form",
            }
        )
    return kills


def texas_routing(profile: dict[str, Any] | None = None) -> dict[str, Any]:
    profile = profile or {}
    kills = texas_kills(profile)
    return {
        **texas_saa_block(),
        "cogs": TEXAS_COGS,
        "cog_label": cog_label(str(profile.get("cog") or "")),
        "kills": kills,
        "killed": bool(kills),
        "applicant_type": applicant_type(profile),
        "city_name": str(profile.get("city_name") or "").strip(),
    }
