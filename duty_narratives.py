"""Narrative frames in a small-town chief's voice. No finished sample town."""

from __future__ import annotations

from typing import Any

BRACKETS = ("[agency]", "[sourced crime]", "[sworn count]", "[sourced population]")

FRAMES = {
    "community_need": (
        "The [agency] is the municipal police department for this town. "
        "We have [sworn count] sworn officers. The people who live here number "
        "[sourced population]. That is the whole of the department. There is no "
        "grant office and no extra shift to write applications."
    ),
    "problem_statement": (
        "The problem we can put on paper is the work already on our ORI. "
        "[sourced crime]. Those figures are for this department only. "
        "If a figure is still in brackets, it is not on this packet yet and "
        "must not be replaced with a number from another town or a website."
    ),
    "project_description": (
        "The city is the applicant in Texas eGrants. The [agency] would carry "
        "out the work if the Criminal Justice Grant Program awards funds. "
        "We are [sworn count] sworn. The request should stay inside what this "
        "town can buy, field, and account for. eGrants is the form; this page is desk prep."
    ),
    "sustainability": (
        "When the pass-through ends, the [agency] will keep the funded work "
        "inside the town budget or stop the extra item. We will not promise "
        "a hire we cannot keep. COPS Hiring retention, if we later apply, is "
        "answered on the FY27 readiness sheet and stays blank until I answer it."
    ),
    "why_this_town": (
        "This town, not a city with a grant writer: the [agency] has "
        "[sworn count] sworn officers for [sourced population], and the chief "
        "writes this packet."
    ),
}


def _text(value: Any) -> str:
    return str(value).strip() if value is not None else ""


def display_agency(profile: dict[str, Any]) -> str:
    name = _text(profile.get("agency_name"))
    return name or "[agency]"


def display_sworn(profile: dict[str, Any]) -> str:
    raw = profile.get("sworn_count")
    if raw in (None, ""):
        return "[sworn count]"
    return str(raw)


def display_population(profile: dict[str, Any]) -> str:
    pop = profile.get("population") or {}
    if pop.get("ok") and pop.get("value") is not None and pop.get("year"):
        return (
            f"{int(pop['value']):,} residents ({pop.get('citation') or pop['year']})"
        )
    return "[sourced population]"


def display_crime(profile: dict[str, Any]) -> str:
    crime = profile.get("crime") or {}
    if crime.get("ok") and crime.get("citation"):
        return crime["citation"]
    return "[sourced crime]"


def fill_frame(template: str, profile: dict[str, Any]) -> str:
    """Replace a bracket only when that sourced field is already on the profile."""
    text = template
    agency = display_agency(profile)
    if agency != "[agency]":
        text = text.replace("[agency]", agency)
    sworn = display_sworn(profile)
    if sworn != "[sworn count]":
        text = text.replace("[sworn count]", sworn)
    population = display_population(profile)
    if population != "[sourced population]":
        text = text.replace("[sourced population]", population)
    crime = display_crime(profile)
    if crime != "[sourced crime]":
        text = text.replace("[sourced crime]", crime)
    return text


def narrative_slots(profile: dict[str, Any]) -> dict[str, str]:
    slots: dict[str, str] = {}
    for key, template in FRAMES.items():
        typed = _text(profile.get(key))
        slots[key] = typed or fill_frame(template, profile)
    use = _text(profile.get("use_of_funds"))
    slots["use_of_funds"] = use or (
        "Use of funds (chief must write the items): [leave blank until listed]"
    )
    return slots


def still_has_unresolved_number(text: str) -> bool:
    return any(token in (text or "") for token in BRACKETS)
