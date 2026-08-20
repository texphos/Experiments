"""Census ACS 5-year (town only) and FBI CDE (this ORI only). Fail closed."""

from __future__ import annotations

import os
import re
from typing import Any, Callable
from urllib.parse import urlparse

import requests

ACS_HOST = "api.census.gov"
GEOCODER_HOST = "geocoding.geo.census.gov"
CDE_HOST = "api.usa.gov"
CDE_PATH_PREFIX = "/crime/fbi/sapi/api/summarized/agencies/"

# Never call these. A blank field is required instead of a substitute number.
BLOCKED_HOSTS = frozenset(
    {
        "crimegrade.org",
        "www.crimegrade.org",
        "city-data.com",
        "www.city-data.com",
        "wikipedia.org",
        "en.wikipedia.org",
        "www.wikipedia.org",
    }
)

ALLOWED_HOSTS = frozenset({ACS_HOST, GEOCODER_HOST, CDE_HOST})

ACS_YEARS = tuple(range(2024, 2018, -1))
CDE_FROM_YEAR = 2019
CDE_THROUGH_YEAR = 2025
ORI_RE = re.compile(r"^[A-Z0-9]{9}$")

Fetcher = Callable[..., Any]


class SourceError(Exception):
    def __init__(self, message: str, *, blank: bool = True):
        super().__init__(message)
        self.blank = blank


def census_key() -> str:
    return (os.environ.get("CENSUS_API_KEY") or "").strip()


def cde_key() -> str:
    return (
        os.environ.get("CDE_API_KEY")
        or os.environ.get("FBI_CDE_API_KEY")
        or os.environ.get("FBI_API_KEY")
        or ""
    ).strip()


def keys_status() -> dict[str, bool]:
    return {
        "census_acs": bool(census_key()),
        "fbi_cde": bool(cde_key()),
    }


def normalize_ori(value: str | None) -> str:
    return re.sub(r"[^A-Z0-9]", "", (value or "").strip().upper())


def assert_ori(ori: str) -> str:
    cleaned = normalize_ori(ori)
    if not ORI_RE.match(cleaned):
        raise SourceError("ORI must be exactly 9 characters (letters and digits).")
    return cleaned


def _host(url: str) -> str:
    return (urlparse(url).hostname or "").lower()


def guarded_get(
    url: str,
    *,
    params: dict[str, Any] | None = None,
    timeout: int = 30,
    fetcher: Fetcher | None = None,
) -> Any:
    host = _host(url)
    if host in BLOCKED_HOSTS:
        raise SourceError(f"Refusing {host}. Duty Packet does not use that site.")
    if host not in ALLOWED_HOSTS:
        raise SourceError(f"Refusing host {host or '(none)'}. Only Census ACS/geocoder and FBI CDE are allowed.")
    get = fetcher or requests.get
    response = get(url, params=params, timeout=timeout)
    return response


def _require_acs5_url(url: str) -> None:
    lowered = url.lower()
    if "/acs/acs1" in lowered or "/acs/acsse" in lowered:
        raise SourceError("ACS 1-year and supplemental estimates are not allowed.")
    if "/acs/acs5" not in lowered:
        raise SourceError("Population may be read only from ACS 5-year.")


def acs5_place_url(year: int, state_fips: str, place_fips: str) -> str:
    return (
        f"https://{ACS_HOST}/data/{year}/acs/acs5"
        f"?get=NAME,B01003_001E"
        f"&for=place:{place_fips}"
        f"&in=state:{state_fips}"
    )


def acs5_cousub_url(year: int, state_fips: str, county_fips: str, cousub_fips: str) -> str:
    return (
        f"https://{ACS_HOST}/data/{year}/acs/acs5"
        f"?get=NAME,B01003_001E"
        f"&for=county%20subdivision:{cousub_fips}"
        f"&in=state:{state_fips}%20county:{county_fips}"
    )


def _blank_population(reason: str) -> dict[str, Any]:
    return {
        "ok": False,
        "value": None,
        "year": None,
        "vintage": None,
        "geography_name": None,
        "geography_kind": None,
        "geoid": None,
        "source": "U.S. Census Bureau, American Community Survey 5-year estimates",
        "citation": "",
        "blank_reason": reason,
        "candidates": [],
    }


def _place_from_geocoder(payload: dict[str, Any], town: str) -> dict[str, Any]:
    matches = (payload.get("result") or {}).get("addressMatches") or []
    if not matches:
        raise SourceError(
            "Census geocoder found no address match for that town. Population left blank."
        )

    incorporated: list[dict[str, Any]] = []
    cdps: list[dict[str, Any]] = []
    cousubs: list[dict[str, Any]] = []
    for match in matches:
        geos = match.get("geographies") or {}
        for row in geos.get("Incorporated Places") or []:
            incorporated.append(row)
        for row in geos.get("Census Designated Places") or []:
            cdps.append(row)
        for row in geos.get("County Subdivisions") or []:
            cousubs.append(row)
        # Counties are read only so we can refuse them. Never query ACS by county.
        _ = geos.get("Counties") or []

    def unique(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
        seen: set[str] = set()
        out: list[dict[str, Any]] = []
        for row in rows:
            geoid = str(row.get("GEOID") or "")
            if not geoid or geoid in seen:
                continue
            seen.add(geoid)
            out.append(row)
        return out

    incorporated = unique(incorporated)
    cdps = unique(cdps)
    cousubs = unique(cousubs)

    chosen = incorporated or cdps
    kind = "place"
    if not chosen:
        town_l = town.strip().lower()
        named = [
            row
            for row in cousubs
            if town_l
            and town_l in str(row.get("NAME") or row.get("BASENAME") or "").lower()
        ]
        if named:
            chosen = named
            kind = "county subdivision"
        else:
            raise SourceError(
                "No Census place or matching county subdivision for that town. "
                "A county figure will not be used. Population left blank."
            )

    if len(chosen) > 1:
        return {
            "ambiguous": True,
            "candidates": [
                {
                    "name": row.get("NAME") or row.get("BASENAME"),
                    "geoid": row.get("GEOID"),
                    "kind": kind,
                }
                for row in chosen
            ],
        }

    row = chosen[0]
    geoid = str(row.get("GEOID") or "")
    if kind == "place":
        if len(geoid) != 7:
            raise SourceError("Census place GEOID was not 7 digits. Population left blank.")
        return {
            "ambiguous": False,
            "kind": "place",
            "state_fips": geoid[:2],
            "place_fips": geoid[2:],
            "county_fips": "",
            "cousub_fips": "",
            "geoid": geoid,
            "name": row.get("NAME") or row.get("BASENAME") or "",
        }

    if len(geoid) != 10:
        raise SourceError(
            "County-subdivision GEOID was not 10 digits. Population left blank."
        )
    return {
        "ambiguous": False,
        "kind": "county subdivision",
        "state_fips": geoid[:2],
        "place_fips": "",
        "county_fips": geoid[2:5],
        "cousub_fips": geoid[5:],
        "geoid": geoid,
        "name": row.get("NAME") or row.get("BASENAME") or "",
    }


def lookup_acs5_population(
    town: str,
    state: str,
    *,
    fetcher: Fetcher | None = None,
) -> dict[str, Any]:
    """Town (place or matching MCD) ACS 5-year only. Never ACS 1-year. Never county."""
    if not census_key():
        return _blank_population(
            "Census ACS is unavailable without an API key. Population left blank."
        )
    if not (town or "").strip() or not (state or "").strip():
        return _blank_population("Town and state are required for an ACS 5-year place lookup.")

    geo_url = "https://geocoding.geo.census.gov/geocoder/geographies/onelineaddress"
    geo_params = {
        "address": f"{town.strip()}, {state.strip()}",
        "benchmark": "Public_AR_Current",
        "vintage": "Current_Current",
        "format": "json",
    }
    try:
        geo_resp = guarded_get(geo_url, params=geo_params, fetcher=fetcher)
        geo_resp.raise_for_status()
        geo = _place_from_geocoder(geo_resp.json(), town)
    except SourceError as exc:
        return _blank_population(str(exc))
    except Exception:
        return _blank_population(
            "Census geocoder did not return a usable town geography. Population left blank."
        )

    if geo.get("ambiguous"):
        result = _blank_population(
            "More than one Census place matched. Choose the town — do not use a county or a neighbor."
        )
        result["candidates"] = geo["candidates"]
        return result

    last_error = "ACS 5-year did not return a row for that town."
    for year in ACS_YEARS:
        if geo["kind"] == "place":
            url = acs5_place_url(year, geo["state_fips"], geo["place_fips"])
        else:
            url = acs5_cousub_url(
                year, geo["state_fips"], geo["county_fips"], geo["cousub_fips"]
            )
        _require_acs5_url(url)
        if "for=county:" in url and "subdivision" not in url:
            raise SourceError("County ACS queries are not allowed for a town.")
        try:
            resp = guarded_get(url, params={"key": census_key()}, fetcher=fetcher)
            if resp.status_code != 200:
                last_error = f"ACS 5-year {year} did not return data for that town."
                continue
            rows = resp.json()
        except Exception:
            last_error = f"ACS 5-year {year} could not be read. Population left blank."
            continue
        if not isinstance(rows, list) or len(rows) < 2:
            continue
        header, values = rows[0], rows[1]
        try:
            name = values[header.index("NAME")]
            raw = values[header.index("B01003_001E")]
            if raw in (None, "", "-999999999"):
                continue
            population = int(raw)
        except (ValueError, KeyError, TypeError):
            continue
        vintage = f"{year - 4}–{year}"
        citation = (
            f"{population:,} residents; U.S. Census Bureau, American Community Survey "
            f"5-year estimates, {vintage} ({year} vintage), table B01003, {name}. "
            f"Town geography only ({geo['kind']}, GEOID {geo['geoid']}). "
            f"Not ACS 1-year. Not a county figure."
        )
        return {
            "ok": True,
            "value": population,
            "year": vintage,
            "vintage": str(year),
            "geography_name": name,
            "geography_kind": geo["kind"],
            "geoid": geo["geoid"],
            "source": "U.S. Census Bureau, American Community Survey 5-year estimates",
            "citation": citation,
            "blank_reason": None,
            "candidates": [],
        }

    return _blank_population(last_error)


def _blank_crime(reason: str, ori: str = "") -> dict[str, Any]:
    return {
        "ok": False,
        "ori": ori,
        "year": None,
        "violent": None,
        "property": None,
        "offenses": [],
        "source": "FBI Crime Data Explorer",
        "citation": "",
        "blank_reason": reason,
        "no_row": "no row" in reason.lower(),
    }


def cde_summarized_url(ori: str, start: int, end: int) -> str:
    return (
        f"https://{CDE_HOST}{CDE_PATH_PREFIX}{ori}/offenses/{start}/{end}"
    )


def lookup_cde_crime(ori: str, *, fetcher: Fetcher | None = None) -> dict[str, Any]:
    """This ORI only. If CDE has no row, leave blank. Never invent a substitute."""
    try:
        cleaned = assert_ori(ori)
    except SourceError as exc:
        return _blank_crime(str(exc))
    if not cde_key():
        return _blank_crime(
            "FBI CDE is unavailable without an API key. Crime figures left blank.",
            cleaned,
        )

    url = cde_summarized_url(cleaned, CDE_FROM_YEAR, CDE_THROUGH_YEAR)
    if "/summarized/agencies/" not in url:
        raise SourceError("CDE URL must be the summarized agency path for this ORI.")
    if cleaned not in url:
        raise SourceError("CDE URL must include the typed ORI and no other agency.")

    try:
        resp = guarded_get(url, params={"api_key": cde_key()}, fetcher=fetcher)
        if resp.status_code == 404:
            return _blank_crime(
                f"FBI CDE has no row for ORI {cleaned}. Crime figures left blank.",
                cleaned,
            )
        resp.raise_for_status()
        payload = resp.json()
    except SourceError as exc:
        return _blank_crime(str(exc), cleaned)
    except Exception:
        return _blank_crime(
            f"FBI CDE did not return a usable row for ORI {cleaned}. Crime figures left blank.",
            cleaned,
        )

    rows = payload.get("results") if isinstance(payload, dict) else None
    if rows is None and isinstance(payload, list):
        rows = payload
    if not rows:
        return _blank_crime(
            f"FBI CDE has no row for ORI {cleaned}. Crime figures left blank.",
            cleaned,
        )

    by_year: dict[int, dict[str, Any]] = {}
    for row in rows:
        row_ori = normalize_ori(str(row.get("ori") or cleaned))
        if row_ori and row_ori != cleaned:
            continue
        try:
            year = int(row.get("data_year") or row.get("year"))
        except (TypeError, ValueError):
            continue
        offense = str(row.get("offense") or row.get("offense_code") or "").lower()
        actual = row.get("actual")
        if actual is None:
            actual = row.get("actual_count")
        if actual is None:
            continue
        try:
            count = int(actual)
        except (TypeError, ValueError):
            continue
        bucket = by_year.setdefault(year, {"offenses": []})
        bucket["offenses"].append({"offense": offense, "actual": count})
        if "violent" in offense:
            bucket["violent"] = count
        if "property" in offense:
            bucket["property"] = count

    if not by_year:
        return _blank_crime(
            f"FBI CDE has no row for ORI {cleaned}. Crime figures left blank.",
            cleaned,
        )

    year = max(by_year)
    data = by_year[year]
    violent = data.get("violent")
    property_c = data.get("property")
    parts = []
    if violent is not None:
        parts.append(f"{violent:,} violent offenses")
    if property_c is not None:
        parts.append(f"{property_c:,} property offenses")
    if not parts:
        listed = ", ".join(
            f"{item['offense']} {item['actual']:,}" for item in data["offenses"][:8]
        )
        parts.append(listed or "offenses on file")
    citation = (
        f"{'; '.join(parts)} known to ORI {cleaned} in {year}; "
        f"FBI Crime Data Explorer (UCR/NIBRS), this ORI only. "
        f"No neighboring agency substituted."
    )
    return {
        "ok": True,
        "ori": cleaned,
        "year": str(year),
        "violent": violent,
        "property": property_c,
        "offenses": data["offenses"],
        "source": "FBI Crime Data Explorer",
        "citation": citation,
        "blank_reason": None,
        "no_row": False,
    }
