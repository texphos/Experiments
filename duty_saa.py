"""State JAG pass-through routing. Not a universal federal JAG form."""

from __future__ import annotations

from typing import Any

# Direct federal JAG Local formula awards are not available when the
# calculated allocation is under $10,000. Those dollars are added to the
# state award; the town applies to its State Administering Agency.
JAG_DIRECT_FLOOR_NOTE = (
    "Direct federal JAG Local formula awards end when the calculated "
    "allocation is under about $10,000. A department of this size applies "
    "to its state for a local pass-through / subaward. This packet is not "
    "a federal JAG application and is not a substitute for the state's "
    "own solicitation or forms."
)

# Official SAA names and public homepages. Solicitations and portals change;
# the chief must open the current local notice. No deadlines are stored here.
SAA: dict[str, dict[str, str]] = {
    "AL": {
        "state": "Alabama",
        "saa": "Alabama Department of Economic and Community Affairs, Law Enforcement and Traffic Safety Division",
        "url": "https://adeca.alabama.gov/lets/",
        "portal": "ADECA grants portal (confirm on the SAA site)",
    },
    "AK": {
        "state": "Alaska",
        "saa": "Alaska Department of Public Safety",
        "url": "https://dps.alaska.gov/",
        "portal": "State DPS grants (confirm on the SAA site)",
    },
    "AZ": {
        "state": "Arizona",
        "saa": "Arizona Criminal Justice Commission",
        "url": "https://www.azcjc.gov/",
        "portal": "ACJC grants (confirm on the SAA site)",
    },
    "AR": {
        "state": "Arkansas",
        "saa": "Arkansas Department of Finance and Administration, Office of Intergovernmental Services",
        "url": "https://www.dfa.arkansas.gov/intergovernmental-services/",
        "portal": "DFA IGS grants (confirm on the SAA site)",
    },
    "CA": {
        "state": "California",
        "saa": "Board of State and Community Corrections",
        "url": "https://www.bscc.ca.gov/",
        "portal": "BSCC grants portal (confirm on the SAA site)",
    },
    "CO": {
        "state": "Colorado",
        "saa": "Colorado Department of Public Safety, Division of Criminal Justice",
        "url": "https://dcj.colorado.gov/",
        "portal": "DCJ grants (confirm on the SAA site)",
    },
    "CT": {
        "state": "Connecticut",
        "saa": "Connecticut Office of Policy and Management",
        "url": "https://portal.ct.gov/opm",
        "portal": "OPM criminal justice grants (confirm on the SAA site)",
    },
    "DE": {
        "state": "Delaware",
        "saa": "Delaware Criminal Justice Council",
        "url": "https://cjc.delaware.gov/",
        "portal": "CJC grants (confirm on the SAA site)",
    },
    "DC": {
        "state": "District of Columbia",
        "saa": "Office of Victim Services and Justice Grants",
        "url": "https://ovsjg.dc.gov/",
        "portal": "OVSJG grants (confirm on the SAA site)",
    },
    "FL": {
        "state": "Florida",
        "saa": "Florida Department of Law Enforcement, Office of Criminal Justice Grants",
        "url": "https://www.fdle.state.fl.us/",
        "portal": "FDLE criminal justice grants (confirm on the SAA site)",
    },
    "GA": {
        "state": "Georgia",
        "saa": "Georgia Criminal Justice Coordinating Council",
        "url": "https://cjcc.georgia.gov/",
        "portal": "CJCC grants (confirm on the SAA site)",
    },
    "HI": {
        "state": "Hawaii",
        "saa": "Hawaii Department of the Attorney General, Crime Prevention and Justice Assistance Division",
        "url": "https://ag.hawaii.gov/cpja/",
        "portal": "AG CPJA grants (confirm on the SAA site)",
    },
    "ID": {
        "state": "Idaho",
        "saa": "Idaho State Police, Planning, Grants and Research",
        "url": "https://isp.idaho.gov/",
        "portal": "ISP Planning, Grants and Research (confirm on the SAA site)",
    },
    "IL": {
        "state": "Illinois",
        "saa": "Illinois Criminal Justice Information Authority",
        "url": "https://icjia.illinois.gov/",
        "portal": "ICJIA grants (confirm on the SAA site)",
    },
    "IN": {
        "state": "Indiana",
        "saa": "Indiana Criminal Justice Institute",
        "url": "https://www.in.gov/cji/",
        "portal": "ICJI IntelliGrants (confirm on the SAA site)",
    },
    "IA": {
        "state": "Iowa",
        "saa": "Iowa Office of Drug Control Policy",
        "url": "https://odcp.iowa.gov/",
        "portal": "ODCP / state justice grants (confirm on the SAA site)",
    },
    "KS": {
        "state": "Kansas",
        "saa": "Kansas Governor's Grants Program",
        "url": "https://www.grants.ks.gov/",
        "portal": "Governor's Grants Program (confirm on the SAA site)",
    },
    "KY": {
        "state": "Kentucky",
        "saa": "Kentucky Justice and Public Safety Cabinet, Grants Management Division",
        "url": "https://www.justice.ky.gov/",
        "portal": "JPSC grants (confirm on the SAA site)",
    },
    "LA": {
        "state": "Louisiana",
        "saa": "Louisiana Commission on Law Enforcement",
        "url": "https://lcle.la.gov/",
        "portal": "LCLE Egrants (confirm on the SAA site)",
    },
    "ME": {
        "state": "Maine",
        "saa": "Maine Department of Public Safety",
        "url": "https://www.maine.gov/dps/",
        "portal": "DPS justice grants (confirm on the SAA site)",
    },
    "MD": {
        "state": "Maryland",
        "saa": "Governor's Office of Crime Prevention and Policy",
        "url": "https://gocpp.maryland.gov/",
        "portal": "GOCPP grants (confirm on the SAA site)",
    },
    "MA": {
        "state": "Massachusetts",
        "saa": "Massachusetts Executive Office of Public Safety and Security",
        "url": "https://www.mass.gov/orgs/executive-office-of-public-safety-and-security",
        "portal": "EOPSS grants (confirm on the SAA site)",
    },
    "MI": {
        "state": "Michigan",
        "saa": "Michigan State Police, Grants and Community Services",
        "url": "https://www.michigan.gov/msp",
        "portal": "MSP grants (confirm on the SAA site)",
    },
    "MN": {
        "state": "Minnesota",
        "saa": "Minnesota Department of Public Safety, Office of Justice Programs",
        "url": "https://dps.mn.gov/divisions/ojp",
        "portal": "DPS OJP grants (confirm on the SAA site)",
    },
    "MS": {
        "state": "Mississippi",
        "saa": "Mississippi Department of Public Safety, Division of Public Safety Planning",
        "url": "https://www.dps.ms.gov/",
        "portal": "DPS Planning grants (confirm on the SAA site)",
    },
    "MO": {
        "state": "Missouri",
        "saa": "Missouri Department of Public Safety",
        "url": "https://dps.mo.gov/",
        "portal": "DPS grants (confirm on the SAA site)",
    },
    "MT": {
        "state": "Montana",
        "saa": "Montana Board of Crime Control",
        "url": "https://mbcc.mt.gov/",
        "portal": "MBCC grants (confirm on the SAA site)",
    },
    "NE": {
        "state": "Nebraska",
        "saa": "Nebraska Crime Commission",
        "url": "https://ncc.nebraska.gov/",
        "portal": "Crime Commission grants (confirm on the SAA site)",
    },
    "NV": {
        "state": "Nevada",
        "saa": "Nevada Department of Public Safety, Office of Criminal Justice Assistance",
        "url": "https://ocj.nv.gov/",
        "portal": "OCJA grants (confirm on the SAA site)",
    },
    "NH": {
        "state": "New Hampshire",
        "saa": "New Hampshire Department of Justice",
        "url": "https://www.doj.nh.gov/",
        "portal": "DOJ grants (confirm on the SAA site)",
    },
    "NJ": {
        "state": "New Jersey",
        "saa": "New Jersey Office of the Attorney General, Office of Justice Programs",
        "url": "https://www.njoag.gov/",
        "portal": "OAG justice grants (confirm on the SAA site)",
    },
    "NM": {
        "state": "New Mexico",
        "saa": "New Mexico Department of Public Safety",
        "url": "https://www.dps.nm.gov/",
        "portal": "DPS grants (confirm on the SAA site)",
    },
    "NY": {
        "state": "New York",
        "saa": "New York State Division of Criminal Justice Services",
        "url": "https://www.criminaljustice.ny.gov/",
        "portal": "DCJS grants management (confirm on the SAA site)",
    },
    "NC": {
        "state": "North Carolina",
        "saa": "North Carolina Governor's Crime Commission",
        "url": "https://www.ncdps.gov/about-dps/boards-and-commissions/governors-crime-commission",
        "portal": "GCC grants (confirm on the SAA site)",
    },
    "ND": {
        "state": "North Dakota",
        "saa": "North Dakota Office of the Attorney General",
        "url": "https://attorneygeneral.nd.gov/",
        "portal": "Attorney General grants (confirm on the SAA site)",
    },
    "OH": {
        "state": "Ohio",
        "saa": "Ohio Office of Criminal Justice Services",
        "url": "https://ocjs.ohio.gov/",
        "portal": "OCJS grants (confirm on the SAA site)",
    },
    "OK": {
        "state": "Oklahoma",
        "saa": "Oklahoma District Attorneys Council",
        "url": "https://www.ok.gov/dac/",
        "portal": "DAC grants (confirm on the SAA site)",
    },
    "OR": {
        "state": "Oregon",
        "saa": "Oregon Criminal Justice Commission",
        "url": "https://www.oregon.gov/cjc/",
        "portal": "CJC grants (confirm on the SAA site)",
    },
    "PA": {
        "state": "Pennsylvania",
        "saa": "Pennsylvania Commission on Crime and Delinquency",
        "url": "https://www.pccd.pa.gov/",
        "portal": "PCCD Egrants (confirm on the SAA site)",
    },
    "RI": {
        "state": "Rhode Island",
        "saa": "Rhode Island Public Safety Grant Administration Office",
        "url": "https://www.ri.gov/",
        "portal": "Public Safety Grant Administration (confirm on the SAA site)",
    },
    "SC": {
        "state": "South Carolina",
        "saa": "South Carolina Department of Public Safety, Office of Highway Safety and Justice Programs",
        "url": "https://scdps.sc.gov/",
        "portal": "SCDPS justice grants (confirm on the SAA site)",
    },
    "SD": {
        "state": "South Dakota",
        "saa": "South Dakota Office of the Attorney General",
        "url": "https://atg.sd.gov/",
        "portal": "Attorney General grants (confirm on the SAA site)",
    },
    "TN": {
        "state": "Tennessee",
        "saa": "Tennessee Department of Finance and Administration, Office of Criminal Justice Programs",
        "url": "https://www.tn.gov/finance/office-of-criminal-justice-programs.html",
        "portal": "OCJP grants (confirm on the SAA site)",
    },
    "TX": {
        "state": "Texas",
        "saa": "Office of the Governor, Public Safety Office",
        "url": "https://gov.texas.gov/organization/public-safety",
        "portal": "Texas eGrants (confirm on the SAA site)",
    },
    "UT": {
        "state": "Utah",
        "saa": "Utah Commission on Criminal and Juvenile Justice",
        "url": "https://justice.utah.gov/",
        "portal": "CCJJ grants (confirm on the SAA site)",
    },
    "VT": {
        "state": "Vermont",
        "saa": "Vermont Department of Public Safety",
        "url": "https://vsp.vermont.gov/",
        "portal": "DPS justice grants (confirm on the SAA site)",
    },
    "VA": {
        "state": "Virginia",
        "saa": "Virginia Department of Criminal Justice Services",
        "url": "https://www.dcjs.virginia.gov/",
        "portal": "DCJS OGMS (confirm on the SAA site)",
    },
    "WA": {
        "state": "Washington",
        "saa": "Washington State Department of Commerce",
        "url": "https://www.commerce.wa.gov/",
        "portal": "Commerce grants (confirm on the SAA site)",
    },
    "WV": {
        "state": "West Virginia",
        "saa": "West Virginia Division of Administrative Services, Justice and Community Services",
        "url": "https://jcs.wv.gov/",
        "portal": "JCS grants (confirm on the SAA site)",
    },
    "WI": {
        "state": "Wisconsin",
        "saa": "Wisconsin Department of Justice, Bureau of Justice Programs",
        "url": "https://www.doj.state.wi.us/",
        "portal": "DOJ BJP Egrants (confirm on the SAA site)",
    },
    "WY": {
        "state": "Wyoming",
        "saa": "Wyoming Office of the Attorney General, Division of Criminal Investigation",
        "url": "https://ag.wyo.gov/",
        "portal": "Attorney General / DCI grants (confirm on the SAA site)",
    },
}


def normalize_state(value: str | None) -> str:
    raw = (value or "").strip().upper()
    if raw in SAA:
        return raw
    for abbr, row in SAA.items():
        if raw == row["state"].upper():
            return abbr
    return ""


def state_packet_title(state_abbr: str) -> str:
    abbr = normalize_state(state_abbr)
    if not abbr:
        return "State JAG pass-through packet (name the state first)"
    name = SAA[abbr]["state"]
    return f"{name} JAG local pass-through application packet"


def saa_for(state_abbr: str) -> dict[str, Any]:
    abbr = normalize_state(state_abbr)
    if not abbr:
        return {
            "ok": False,
            "state_abbr": "",
            "state": "",
            "saa": "",
            "url": "",
            "portal": "",
            "program": "",
            "direct_floor_note": JAG_DIRECT_FLOOR_NOTE,
            "form_warning": (
                "Name the state. Duty Packet will not invent a universal JAG form."
            ),
        }
    row = SAA[abbr]
    return {
        "ok": True,
        "state_abbr": abbr,
        "state": row["state"],
        "saa": row["saa"],
        "url": row["url"],
        "portal": row["portal"],
        "program": (
            f"{row['state']} Edward Byrne Memorial JAG — local pass-through "
            f"for less-than-$10,000 jurisdictions"
        ),
        "direct_floor_note": JAG_DIRECT_FLOOR_NOTE,
        "form_warning": (
            f"This is a packet for the {row['state']} SAA, not a federal JAG "
            f"PDF and not {row['saa']}'s official application form. Attach "
            f"these pages to the current local solicitation on {row['url']}."
        ),
    }


def list_states() -> list[dict[str, str]]:
    return [
        {"abbr": abbr, "name": row["state"]}
        for abbr, row in sorted(SAA.items(), key=lambda item: item[1]["state"])
    ]
