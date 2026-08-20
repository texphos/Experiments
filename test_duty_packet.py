"""Duty Packet rules: fail closed, no invented stats, state JAG, CHP readiness."""

from __future__ import annotations

import io
import os
import zipfile
from datetime import date
import duty_narratives as narratives
import duty_packet as packet
import duty_saa as saa
import duty_sources as sources


class FakeResp:
    def __init__(self, payload, status=200):
        self._payload = payload
        self.status_code = status

    def json(self):
        return self._payload

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"http {self.status_code}")


def test_acs_and_cde_fail_closed_without_keys(monkeypatch):
    monkeypatch.delenv("CENSUS_API_KEY", raising=False)
    monkeypatch.delenv("CDE_API_KEY", raising=False)
    monkeypatch.delenv("FBI_CDE_API_KEY", raising=False)
    monkeypatch.delenv("FBI_API_KEY", raising=False)
    pop = sources.lookup_acs5_population("Hico", "TX")
    crime = sources.lookup_cde_crime("TX1234500")
    assert pop["value"] is None
    assert pop["ok"] is False
    assert "without an API key" in pop["blank_reason"]
    assert crime["violent"] is None
    assert crime["property"] is None
    assert crime["ok"] is False
    assert "without an API key" in crime["blank_reason"]


def test_acs_urls_are_five_year_place_never_county_or_acs1():
    place = sources.acs5_place_url(2023, "48", "33608")
    cousub = sources.acs5_cousub_url(2023, "09", "001", "12345")
    assert "/acs/acs5" in place and "/acs/acs1" not in place
    assert "for=place:" in place
    assert "for=county:" not in place or "subdivision" in place
    assert "/acs/acs5" in cousub
    assert "county%20subdivision" in cousub
    sources._require_acs5_url(place)
    try:
        sources._require_acs5_url("https://api.census.gov/data/2023/acs/acs1?get=NAME")
        assert False, "ACS 1-year must be rejected"
    except sources.SourceError:
        pass


def test_blocked_hosts_never_used():
    for host in ("crimegrade.org", "www.city-data.com", "en.wikipedia.org"):
        try:
            sources.guarded_get(f"https://{host}/x")
            assert False, host
        except sources.SourceError as exc:
            assert "Refusing" in str(exc)


def test_cde_empty_row_stays_blank(monkeypatch):
    monkeypatch.setenv("CDE_API_KEY", "test-key")

    def fake_get(url, params=None, timeout=30):
        assert "TX1234500" in url
        assert "/summarized/agencies/TX1234500/" in url
        return FakeResp({"results": []})

    result = sources.lookup_cde_crime("TX1234500", fetcher=fake_get)
    assert result["ok"] is False
    assert result["no_row"] is True
    assert result["violent"] is None
    assert "no row" in result["blank_reason"].lower()


def test_cde_ignores_another_ori(monkeypatch):
    monkeypatch.setenv("CDE_API_KEY", "test-key")

    def fake_get(url, params=None, timeout=30):
        return FakeResp(
            {
                "results": [
                    {
                        "ori": "TX9999999",
                        "data_year": 2024,
                        "offense": "violent-crime",
                        "actual": 88,
                    }
                ]
            }
        )

    result = sources.lookup_cde_crime("TX1234500", fetcher=fake_get)
    assert result["ok"] is False
    assert result["violent"] is None


def test_acs_uses_place_not_county(monkeypatch):
    monkeypatch.setenv("CENSUS_API_KEY", "test-key")
    calls = []

    def fake_get(url, params=None, timeout=30):
        calls.append(url)
        if "geocoding" in url:
            return FakeResp(
                {
                    "result": {
                        "addressMatches": [
                            {
                                "geographies": {
                                    "Incorporated Places": [
                                        {"GEOID": "4833608", "NAME": "Hico city, Texas"}
                                    ],
                                    "Counties": [
                                        {"GEOID": "48143", "NAME": "Hamilton County"}
                                    ],
                                }
                            }
                        ]
                    }
                }
            )
        return FakeResp(
            [
                ["NAME", "B01003_001E", "state", "place"],
                ["Hico city, Texas", "1342", "48", "33608"],
            ]
        )

    result = sources.lookup_acs5_population("Hico", "TX", fetcher=fake_get)
    assert result["ok"] is True
    assert result["value"] == 1342
    assert "2020–2024" in result["year"] or result["year"]
    assert "Not ACS 1-year" in result["citation"]
    assert "Not a county" in result["citation"]
    acs_urls = [url for url in calls if "api.census.gov" in url]
    assert acs_urls
    assert all("/acs/acs5" in url for url in acs_urls)
    assert all("for=place:" in url for url in acs_urls)
    assert all("acs1" not in url for url in acs_urls)


def test_narratives_keep_brackets_and_never_sample_town():
    slots = narratives.narrative_slots({})
    assert "[agency]" in slots["community_need"]
    assert "[sourced crime]" in slots["problem_statement"]
    assert "[sworn count]" in slots["why_this_town"]
    blob = " ".join(slots.values()).lower()
    for banned in ("springfield", "mayberry", "sample town", "anyltown"):
        assert banned not in blob


def test_narrative_numbers_only_from_sourced_fields():
    profile = {
        "agency_name": "Hico Police Department",
        "sworn_count": 6,
        "population": {
            "ok": True,
            "value": 1342,
            "year": "2020–2024",
            "citation": "1,342 residents; ACS 5-year 2020–2024, Hico city, Texas",
        },
        "crime": {"ok": False, "citation": ""},
    }
    text = narratives.fill_frame(narratives.FRAMES["community_need"], profile)
    assert "Hico Police Department" in text
    assert "6" in text
    assert "1,342" in text
    assert "[sourced crime]" in narratives.fill_frame(
        narratives.FRAMES["problem_statement"], profile
    )


def test_chp_match_and_retention_blank_until_chief():
    review = packet.completeness(
        {
            "agency_name": "Hico Police Department",
            "ori": "TX1234500",
            "state": "TX",
            "town": "Hico",
            "sworn_count": 6,
            "chief_name": "Jane Chief",
            "mayor_name": "John Mayor",
            "population": {
                "ok": True,
                "value": 1342,
                "year": "2020–2024",
                "citation": "1,342 (ACS 5-year)",
            },
            "crime": {"ok": True, "citation": "4 violent offenses in 2024; FBI CDE ORI TX1234500"},
            "use_of_funds": "One patrol vehicle radio.",
            "saa_solicitation_confirmed": True,
            "sam_current": True,
            "uei": "ABCDEFGHIJKL",
            "grants_gov_ready": True,
            "justgrants_ready": True,
            "two_aors": True,
            "chp_positions": "1",
        }
    )
    items = " ".join(row["item"] for row in review["owed"])
    assert "25%" in items or "match" in items.lower()
    assert "12-month" in items
    assert review["ready"] is False


def test_incomplete_packet_does_not_look_finished():
    review = packet.completeness({})
    assert review["ready"] is False
    assert "INCOMPLETE" in review["banner"]
    assert any(row["who"] == "chief" for row in review["owed"])
    assert any(row["who"] == "mayor" for row in review["owed"])
    pdf = packet.render_jag_pdf({}, review)
    assert pdf.startswith(b"%PDF")
    assert b"INCOMPLETE PACKET" in pdf


def test_state_jag_is_not_universal():
    tx = saa.saa_for("TX")
    assert tx["ok"] is True
    assert "Texas" in tx["program"]
    assert "Public Safety Office" in tx["saa"]
    assert "not a federal jag" in tx["form_warning"].lower()
    empty = saa.saa_for("")
    assert empty["ok"] is False
    assert "universal" in empty["form_warning"].lower()
    title = saa.state_packet_title("TX")
    assert title.startswith("Texas JAG")
    assert "universal" not in title.lower()


def test_filename_uses_agency_grant_and_date():
    names = packet.packet_filenames(
        {"agency_name": "Hico Police Department", "state": "TX"},
        when=date(2026, 8, 20),
    )
    assert names["jag"] == "Hico-Police-Department_TX-JAG-Passthrough_2026-08-20.pdf"
    assert names["chp"] == "Hico-Police-Department_FY27-CHP-Readiness_2026-08-20.pdf"
    assert "2026-08-20" in names["zip"]


def test_chp_sheet_is_readiness_not_fy26_application():
    pdf = packet.render_chp_pdf({"agency_name": "Hico Police Department", "state": "TX"})
    low = pdf.lower()
    assert b"fy27 cops hiring" in low
    assert b"not an fy26" in low
    assert b"does not scrape cops" in low
    assert b"does not print a deadline" in low


def test_zip_contains_both_dated_pdfs():
    name, data = packet.render_zip(
        {"agency_name": "Hico Police Department", "state": "TX"},
        when=date(2026, 8, 20),
    )
    assert name.endswith("_2026-08-20.zip")
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        names = zf.namelist()
    assert any("JAG-Passthrough" in n for n in names)
    assert any("FY27-CHP-Readiness" in n for n in names)


def test_server_does_not_submit_and_keys_report(monkeypatch):
    monkeypatch.delenv("CENSUS_API_KEY", raising=False)
    monkeypatch.delenv("CDE_API_KEY", raising=False)
    from server import app

    client = app.test_client()
    status = client.get("/api/status").get_json()
    assert status["submits_grants_gov"] is False
    assert status["submits_justgrants"] is False
    assert status["scrapes_cops"] is False
    assert status["hardcoded_deadlines"] is False
    assert status["keys"]["census_acs"] is False
    assert status["keys"]["fbi_cde"] is False
    html = client.get("/").data.decode()
    assert "Duty Packet" in html
    assert "Nothing is filed" in html


def test_no_deadline_constants_in_app_modules():
    root = os.path.dirname(os.path.abspath(__file__))
    banned = ("due date", "closes on", "deadline:", "nofo close")
    for name in ("server.py", "duty_packet.py", "duty_saa.py", "index.html"):
        text = open(os.path.join(root, name), encoding="utf-8").read().lower()
        for token in banned:
            assert token not in text, f"{name} contains {token}"
