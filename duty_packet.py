"""Completeness, city-hall PDFs, and dated filenames."""

from __future__ import annotations

import io
import re
import zipfile
from datetime import date
from pathlib import Path
from typing import Any

from reportlab.lib.colors import Color, HexColor
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

from duty_narratives import narrative_slots, still_has_unresolved_number
from duty_saa import saa_for, state_packet_title
from duty_texas import PROGRAM_NAME, texas_routing

CREAM = HexColor("#F7F1E6")
INK = HexColor("#1B2430")
RULE = HexColor("#8A8174")
WARN = HexColor("#6B1D1D")
MARGIN = 1.0 * inch
SEAL = 0.7 * inch

SLOT_LABELS = {
    "community_need": "Community need",
    "problem_statement": "Problem statement",
    "project_description": "Project description",
    "use_of_funds": "Use of funds",
    "sustainability": "Sustainability / retention",
    "why_this_town": "Why this town, not a city with a grant writer",
}


def _register_fonts() -> dict[str, str]:
    root = Path(__file__).resolve().parent / "fonts"
    regular = root / "EBGaramond-Regular.ttf"
    bold = root / "EBGaramond-Bold.ttf"
    italic = root / "EBGaramond-Italic.ttf"
    if regular.is_file() and bold.is_file() and italic.is_file():
        if "EBGaramond" not in pdfmetrics.getRegisteredFontNames():
            pdfmetrics.registerFont(TTFont("EBGaramond", str(regular)))
            pdfmetrics.registerFont(TTFont("EBGaramond-Bold", str(bold)))
            pdfmetrics.registerFont(TTFont("EBGaramond-Italic", str(italic)))
        return {
            "roman": "EBGaramond",
            "bold": "EBGaramond-Bold",
            "italic": "EBGaramond-Italic",
        }
    return {"roman": "Times-Roman", "bold": "Times-Bold", "italic": "Times-Italic"}


FONTS = _register_fonts()


def _present(value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    return True


def completeness(profile: dict[str, Any]) -> dict[str, Any]:
    owed: list[dict[str, str]] = []
    notes: list[str] = []

    def owe(who: str, item: str, rule: str = "") -> None:
        row = {"who": who, "item": item}
        if rule:
            row["rule"] = rule
        owed.append(row)

    profile = dict(profile)
    profile.setdefault("state", "TX")
    routing = texas_routing(profile)
    for kill in routing["kills"]:
        owe(kill["who"], kill["item"], kill.get("rule") or "")

    if not _present(profile.get("agency_name")):
        owe("chief", "Agency name (implementing department — not the eGrants applicant)")
    ori = (profile.get("ori") or "").strip().upper()
    if len(re.sub(r"[^A-Z0-9]", "", ori)) != 9:
        owe("chief", "9-character ORI")
    if not _present(profile.get("town")):
        owe("chief", "Town name for the ACS 5-year place lookup")
    if not _present(profile.get("sworn_count")):
        owe("chief", "Sworn officer count")
    if not _present(profile.get("chief_name")):
        owe("chief", "Chief name — signature line")
    if not _present(profile.get("mayor_name")):
        owe("mayor", "Mayor name — signature line (city CEO, not a clerk)")

    pop = profile.get("population") or {}
    if not pop.get("ok"):
        reason = pop.get("blank_reason") or "Population is blank."
        notes.append(reason)
        owe(
            "source",
            "Sourced ACS 5-year population for this town (do not write in a county or another website)",
        )

    crime = profile.get("crime") or {}
    if crime.get("no_row"):
        notes.append(
            crime.get("blank_reason")
            or "FBI CDE has no row for this ORI. Crime left blank."
        )
    elif not crime.get("ok"):
        reason = crime.get("blank_reason") or "Crime is blank."
        notes.append(reason)
        owe(
            "source",
            "Sourced FBI CDE crime for this ORI (do not substitute another agency or website)",
        )

    if not _present(profile.get("use_of_funds")):
        owe("chief", "Use of funds — what the city would buy if eGrants awards")

    if not _present(profile.get("chp_match")):
        owe("chief", "CHP 25% cash match or waiver — stays blank until the chief answers")
    if not _present(profile.get("chp_retention")):
        owe(
            "chief",
            "CHP 12-month post-grant retention — stays blank until the chief answers",
        )
    if not _present(profile.get("chp_positions")):
        owe("chief", "CHP readiness: number of entry-level positions contemplated")

    if not profile.get("sam_current"):
        owe(
            "mayor",
            "SAM.gov current, including the annual notarized Entity Administrator letter",
        )
    if not _present(profile.get("uei")):
        owe("mayor", "SAM.gov Unique Entity ID (UEI)")
    if not profile.get("two_aors"):
        owe(
            "mayor",
            "Two Authorized Representatives for any later COPS filing: chief and mayor, not a clerk",
        )

    slots = narrative_slots(profile)
    for key, label in SLOT_LABELS.items():
        text = slots.get(key) or ""
        if key == "use_of_funds" and not _present(profile.get("use_of_funds")):
            continue
        if still_has_unresolved_number(text) and key != "use_of_funds":
            notes.append(f"{label} still has a bracketed field that is not sourced.")

    notes.append(routing["window_note"])
    notes.append(routing["county_essential_note"])

    ready = not owed
    return {
        "ready": ready,
        "draft": not ready,
        "owed": owed,
        "notes": notes,
        "slots": slots,
        "saa": routing,
        "routing": routing,
        "banner": (
            "Desk prep is complete. File in eGrants — this packet is not the form."
            if ready
            else "DRAFT — required fields are empty. Listed by who owes them."
        ),
    }


def slug_agency(name: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9]+", "-", (name or "").strip()).strip("-")
    return cleaned or "Agency"


def packet_filenames(profile: dict[str, Any], when: date | None = None) -> dict[str, str]:
    when = when or date.today()
    stamp = when.isoformat()
    city = slug_agency(str(profile.get("city_name") or ""))
    agency = slug_agency(str(profile.get("agency_name") or "Agency"))
    who = city or agency
    return {
        "jag": f"{who}_TX-CJGP-DeskPrep_{stamp}.pdf",
        "chp": f"{who}_FY27-CHP-Readiness_{stamp}.pdf",
        "zip": f"{who}_DutyPacket_{stamp}.zip",
    }


def _wrap_canvas(c: canvas.Canvas, text: str, font: str, size: float, width: float) -> list[str]:
    words = (text or "").split()
    if not words:
        return [""]
    lines = [""]
    for word in words:
        trial = (lines[-1] + " " + word).strip()
        if c.stringWidth(trial, font, size) <= width:
            lines[-1] = trial
        else:
            lines.append(word)
    return lines


class CityHallPDF:
    def __init__(
        self,
        buf: io.BytesIO,
        profile: dict[str, Any],
        review: dict[str, Any],
        *,
        grant: str,
        when: date | None = None,
    ):
        self.buf = buf
        self.profile = profile
        self.review = review
        self.grant = grant
        self.when = when or date.today()
        self.c = canvas.Canvas(buf, pagesize=letter, pageCompression=0)
        self.width, self.height = letter
        self.page = 0
        self._current_kicker = ""

    def new_page(self, kicker: str) -> None:
        if self.page:
            self.c.showPage()
        self.page += 1
        self._current_kicker = kicker
        c = self.c
        c.setFillColor(CREAM)
        c.rect(0, 0, self.width, self.height, fill=1, stroke=0)
        self._empty_ring(MARGIN + SEAL / 2, self.height - MARGIN - SEAL / 2)
        c.setFillColor(INK)
        c.setFont(FONTS["bold"], 16)
        title = (
            str(self.profile.get("city_name") or "").strip()
            or str(self.profile.get("agency_name") or "").strip()
            or "Municipal packet"
        )
        c.drawString(MARGIN + SEAL + 14, self.height - MARGIN - 22, title)
        c.setFont(FONTS["italic"], 10)
        c.drawString(MARGIN + SEAL + 14, self.height - MARGIN - 38, kicker)
        c.setStrokeColor(INK)
        c.setLineWidth(0.6)
        c.line(MARGIN, self.height - MARGIN - SEAL - 10, self.width - MARGIN, self.height - MARGIN - SEAL - 10)
        footer = " · ".join(
            [
                str(self.profile.get("agency_name") or "Agency"),
                self.grant,
                self.when.isoformat(),
                f"page {self.page}",
            ]
        )
        c.setFont(FONTS["roman"], 9)
        c.drawCentredString(self.width / 2, 0.55 * inch, footer)
        if self.review.get("draft") or not self.review.get("ready"):
            c.setFont(FONTS["bold"], 11)
            c.setFillColor(WARN)
            c.drawCentredString(self.width / 2, self.height - MARGIN - SEAL - 26, "DRAFT")
            c.saveState()
            c.translate(self.width / 2, self.height / 2)
            c.rotate(34)
            c.setFillColor(HexColor("#D9C8B8"))
            c.setFont(FONTS["bold"], 54)
            c.drawCentredString(0, 0, "DRAFT")
            c.restoreState()
            c.setFillColor(INK)

    def _empty_ring(self, x: float, y: float) -> None:
        c = self.c
        c.setStrokeColor(INK)
        c.setLineWidth(1.1)
        c.circle(x, y, SEAL / 2, fill=0, stroke=1)
        c.setLineWidth(0.4)
        c.circle(x, y, SEAL / 2 - 4, fill=0, stroke=1)

    def _body_top(self) -> float:
        extra = 22 if (self.review.get("draft") or not self.review.get("ready")) else 0
        return self.height - MARGIN - SEAL - 24 - extra

    def heading(self, y: float, text: str) -> float:
        self.c.setFillColor(INK)
        self.c.setFont(FONTS["bold"], 12)
        self.c.drawString(MARGIN, y, text)
        self.c.setStrokeColor(RULE)
        self.c.setLineWidth(0.5)
        self.c.line(MARGIN, y - 4, self.width - MARGIN, y - 4)
        return y - 20

    def para(self, y: float, text: str, *, italic: bool = False, color: Color | None = None) -> float:
        font = FONTS["italic"] if italic else FONTS["roman"]
        self.c.setFillColor(color or INK)
        self.c.setFont(font, 10.5)
        width = self.width - 2 * MARGIN
        for line in _wrap_canvas(self.c, text, font, 10.5, width):
            if y < MARGIN + 16:
                self.new_page(self._current_kicker)
                y = self._body_top()
                self.c.setFillColor(color or INK)
                self.c.setFont(font, 10.5)
            self.c.drawString(MARGIN, y, line)
            y -= 14
        return y - 6

    def field(self, y: float, label: str, value: str, *, blank: bool = False) -> float:
        self.c.setFillColor(INK)
        self.c.setFont(FONTS["bold"], 9)
        self.c.drawString(MARGIN, y, label.upper())
        y -= 14
        shown = value if value else "—"
        font = FONTS["italic"] if blank or not value else FONTS["roman"]
        self.c.setFillColor(WARN if blank or not value else INK)
        self.c.setFont(font, 10.5)
        width = self.width - 2 * MARGIN
        for line in _wrap_canvas(self.c, shown, font, 10.5, width):
            if y < MARGIN + 16:
                self.new_page(self._current_kicker)
                y = self._body_top()
            self.c.drawString(MARGIN, y, line)
            y -= 14
        self.c.setStrokeColor(RULE)
        self.c.setLineWidth(0.35)
        self.c.line(MARGIN, y + 8, self.width - MARGIN, y + 8)
        return y - 4

    def signatures(self, y: float) -> float:
        y = self.heading(y, "Signatures")
        y = self.para(
            y,
            "The mayor signs for the city. The chief signs for the department. A clerk is not enough.",
            italic=True,
        )
        chief = str(self.profile.get("chief_name") or "").strip() or "[chief]"
        mayor = str(self.profile.get("mayor_name") or "").strip() or "[mayor]"
        self.c.setStrokeColor(INK)
        self.c.setLineWidth(0.6)
        self.c.setFillColor(INK)
        self.c.setFont(FONTS["roman"], 10)
        left = MARGIN
        right = self.width / 2 + 10
        line_w = 2.6 * inch
        self.c.line(left, y, left + line_w, y)
        self.c.line(right, y, right + line_w, y)
        y -= 14
        self.c.drawString(left, y, f"Chief of police  {chief}")
        self.c.drawString(right, y, f"Mayor  {mayor}")
        return y - 22

    def build_jag(self) -> None:
        self._current_kicker = state_packet_title("TX")
        self.new_page(self._current_kicker)
        y = self._body_top()
        saa = self.review["saa"]
        y = self.heading(y, "Texas desk — not the application")
        y = self.para(y, saa.get("form_warning") or "")
        y = self.para(y, saa.get("direct_floor_note") or "", italic=True)
        y = self.para(y, saa.get("window_note") or "", italic=True)
        y = self.para(y, saa.get("county_essential_note") or "", italic=True)
        y = self.field(y, "State administering agency", saa.get("saa") or "")
        y = self.field(y, "Program (vehicle)", saa.get("program") or "")
        y = self.field(y, "File in eGrants", saa.get("portal_url") or "")
        y = self.field(
            y,
            "Legal applicant",
            str(self.profile.get("city_name") or ""),
            blank=not self.profile.get("city_name"),
        )
        y = self.field(
            y,
            "Applicant type",
            "City — required. Do not apply as the police department.",
            blank=self.review["routing"].get("applicant_type") != "city",
        )
        y = self.field(
            y,
            "Regional council of governments",
            self.review["routing"].get("cog_label") or "",
            blank=not self.review["routing"].get("cog_label"),
        )

        y = self.heading(y, "Agency profile")
        y = self.field(y, "Implementing department", str(self.profile.get("agency_name") or ""), blank=not self.profile.get("agency_name"))
        y = self.field(y, "ORI", str(self.profile.get("ori") or ""), blank=not self.profile.get("ori"))
        y = self.field(
            y,
            "Town (ACS 5-year place)",
            str(self.profile.get("town") or ""),
            blank=not self.profile.get("town"),
        )
        y = self.field(
            y,
            "Sworn officers",
            str(self.profile.get("sworn_count") or ""),
            blank=not _present(self.profile.get("sworn_count")),
        )
        pop = self.profile.get("population") or {}
        y = self.field(
            y,
            "Population (ACS 5-year, this town only)",
            pop.get("citation") or pop.get("blank_reason") or "",
            blank=not pop.get("ok"),
        )
        crime = self.profile.get("crime") or {}
        y = self.field(
            y,
            "Crime (FBI CDE, this ORI only)",
            crime.get("citation") or crime.get("blank_reason") or "",
            blank=not crime.get("ok"),
        )

        self.new_page(self._current_kicker)
        y = self._body_top()
        y = self.heading(y, "Narrative frames")
        y = self.para(
            y,
            "Written in the chief's voice. Brackets stay until the sourced field is on this packet. "
            "No sample town is supplied. Every number in prose must already sit in a sourced field.",
            italic=True,
        )
        slots = self.review["slots"]
        for key, label in SLOT_LABELS.items():
            y = self.field(
                y,
                label,
                slots.get(key) or "",
                blank=still_has_unresolved_number(slots.get(key) or "")
                or (key == "use_of_funds" and not _present(self.profile.get("use_of_funds"))),
            )

        self.new_page("Texas filing checklist — desk prep only")
        y = self._body_top()
        y = self.heading(y, "Rules that kill a packet if skipped")
        checks = [
            (
                "City applicant",
                "The CITY files. The police department is the implementing agency only.",
                self.review["routing"].get("applicant_type") == "city" and bool(self.profile.get("city_name")),
            ),
            (
                "Regional COG first",
                "All 24 councils run their own workshop and priority list. PSO will bounce a skip.",
                bool(self.review["routing"].get("cog_label") and self.profile.get("cog_first")),
            ),
            (
                "CEO / Law Enforcement Certifications",
                "Upload that form in eGrants. This desk does not produce it.",
                bool(self.profile.get("ceo_le_certifications")),
            ),
            (
                "eGrants is the form",
                "File at eGrants. This packet is not a Texas JAG PDF.",
                bool(self.profile.get("egrants_is_the_form")),
            ),
            (
                "County CCH (counties only)",
                "A county filing needs 90%+ CCH disposition completeness at DPS. Municipal PDs do not file as the county.",
                self.review["routing"].get("applicant_type") != "county" or bool(self.profile.get("cch_90")),
            ),
            (
                "County Essential Services",
                "Invitation-only to counties. Municipal PDs ignore it.",
                True,
            ),
            (
                "SAM.gov",
                "Registration current. Unique Entity ID on file. Annual notarized Entity Administrator letter on file.",
                bool(self.profile.get("sam_current") and self.profile.get("uei")),
            ),
        ]
        for title, detail, done in checks:
            mark = "[X]" if done else "[ ]"
            y = self.para(y, f"{mark}  {title} — {detail}", color=INK if done else WARN)

        y = self.heading(y, "Items still owed")
        if self.review["ready"]:
            y = self.para(y, "No required blanks remain on this desk packet.")
        else:
            for item in self.review["owed"]:
                y = self.para(y, f"{item['who'].title()} owes: {item['item']}", color=WARN)
        y = self.signatures(y)
        self.c.save()

    def build_chp(self) -> None:
        self._current_kicker = (
            "FY27 COPS Hiring Program — readiness sheet (not an FY26 CHP application)"
        )
        self.new_page(self._current_kicker)
        y = self._body_top()
        y = self.heading(y, "Readiness only")
        y = self.para(
            y,
            "The FY26 COPS Hiring window is closed. This sheet is not an FY26 application "
            "and not a live FY27 application. Duty Packet does not scrape COPS and does not "
            "print a deadline. When a window opens, it is tracked outside this app. "
            "This sheet is not filed to Grants.gov or JustGrants.",
        )
        y = self.field(y, "City (legal applicant if a later CHP is filed)", str(self.profile.get("city_name") or ""), blank=not self.profile.get("city_name"))
        y = self.field(y, "Agency", str(self.profile.get("agency_name") or ""), blank=not self.profile.get("agency_name"))
        y = self.field(y, "ORI", str(self.profile.get("ori") or ""), blank=not self.profile.get("ori"))
        y = self.field(
            y,
            "Sworn officers now",
            str(self.profile.get("sworn_count") or ""),
            blank=not _present(self.profile.get("sworn_count")),
        )
        y = self.field(
            y,
            "Entry-level positions contemplated",
            str(self.profile.get("chp_positions") or ""),
            blank=not _present(self.profile.get("chp_positions")),
        )
        match = str(self.profile.get("chp_match") or "").strip()
        y = self.heading(y, "25 percent local cash match, or a waiver")
        y = self.para(
            y,
            "CHP requires a 25 percent local cash match unless a waiver is approved with the "
            "application. In-kind does not count. This line stays blank until the chief answers.",
        )
        y = self.field(y, "Chief's answer (match or waiver)", match, blank=not match)
        retention = str(self.profile.get("chp_retention") or "").strip()
        y = self.heading(y, "Twelve-month post-grant retention")
        y = self.para(
            y,
            "Each CHP-funded position must be kept for at least 12 months after federal funding "
            "for that position ends, added to the local budget, not absorbed by attrition. "
            "This line stays blank until the chief answers.",
        )
        y = self.field(y, "Chief's answer (retention)", retention, blank=not retention)
        y = self.heading(y, "Authorized Representatives — not a clerk")
        y = self.field(y, "Top law-enforcement executive (chief)", str(self.profile.get("chief_name") or ""), blank=not self.profile.get("chief_name"))
        y = self.field(y, "Top government executive (mayor)", str(self.profile.get("mayor_name") or ""), blank=not self.profile.get("mayor_name"))
        pop = self.profile.get("population") or {}
        crime = self.profile.get("crime") or {}
        y = self.heading(y, "Sourced figures already on the packet")
        y = self.field(y, "Population", pop.get("citation") or pop.get("blank_reason") or "[sourced population]", blank=not pop.get("ok"))
        y = self.field(y, "Crime", crime.get("citation") or crime.get("blank_reason") or "[sourced crime]", blank=not crime.get("ok"))
        y = self.heading(y, "Items still owed")
        if self.review["ready"]:
            y = self.para(y, "No blanks remain on the readiness sheet.")
        else:
            for item in self.review["owed"]:
                y = self.para(y, f"{item['who'].title()} owes: {item['item']}", color=WARN)
        y = self.signatures(y)
        self.c.save()


def render_jag_pdf(profile: dict[str, Any], review: dict[str, Any] | None = None) -> bytes:
    review = review or completeness(profile)
    buf = io.BytesIO()
    CityHallPDF(buf, profile, review, grant=f"Texas {PROGRAM_NAME} desk prep").build_jag()
    return buf.getvalue()


def render_chp_pdf(profile: dict[str, Any], review: dict[str, Any] | None = None) -> bytes:
    review = review or completeness(profile)
    buf = io.BytesIO()
    CityHallPDF(buf, profile, review, grant="FY27 CHP readiness").build_chp()
    return buf.getvalue()


def render_zip(profile: dict[str, Any], when: date | None = None) -> tuple[str, bytes]:
    review = completeness(profile)
    names = packet_filenames(profile, when)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(names["jag"], render_jag_pdf(profile, review))
        zf.writestr(names["chp"], render_chp_pdf(profile, review))
    return names["zip"], buf.getvalue()
