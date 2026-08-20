"""Completeness, city-hall PDFs, and dated filenames."""

from __future__ import annotations

import io
import re
import zipfile
from datetime import date
from typing import Any

from reportlab.lib.colors import Color, HexColor
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.pdfgen import canvas

from duty_narratives import narrative_slots, still_has_unresolved_number
from duty_saa import saa_for, state_packet_title

NAVY = HexColor("#1B365D")
GOLD = HexColor("#B8952C")
CREAM = HexColor("#F7F1E3")
INK = HexColor("#1A1A1A")
RULE = HexColor("#C4B8A0")
WARN = HexColor("#7A1F1F")
PAPER = HexColor("#FBF7EE")

SLOT_LABELS = {
    "community_need": "Community need",
    "problem_statement": "Problem statement",
    "project_description": "Project description",
    "use_of_funds": "Use of funds",
    "sustainability": "Sustainability / retention",
    "why_this_town": "Why this town, not a city with a grant writer",
}


def _present(value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    return True


def completeness(profile: dict[str, Any]) -> dict[str, Any]:
    owed: list[dict[str, str]] = []
    notes: list[str] = []

    def owe(who: str, item: str) -> None:
        owed.append({"who": who, "item": item})

    if not _present(profile.get("agency_name")):
        owe("chief", "Agency name")
    ori = (profile.get("ori") or "").strip().upper()
    if len(re.sub(r"[^A-Z0-9]", "", ori)) != 9:
        owe("chief", "9-character ORI")
    if not _present(profile.get("state")):
        owe("chief", "State (required to name the JAG pass-through SAA)")
    if not _present(profile.get("town")):
        owe("chief", "Town name for the ACS 5-year place lookup")
    if not _present(profile.get("sworn_count")):
        owe("chief", "Sworn officer count")
    if not _present(profile.get("chief_name")):
        owe("chief", "Chief name (COPS Authorized Representative)")
    if not _present(profile.get("mayor_name")):
        owe("mayor", "Mayor name (COPS Authorized Representative — not a clerk)")

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

    saa = saa_for(str(profile.get("state") or ""))
    if not saa.get("ok"):
        owe("chief", "State so the packet can name the SAA — no universal JAG form")

    if not _present(profile.get("use_of_funds")):
        owe("chief", "Use of funds — what the pass-through would buy")
    if not profile.get("saa_solicitation_confirmed"):
        owe(
            "chief",
            "Confirm the current local JAG solicitation on the SAA site (this app does not scrape windows)",
        )

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
    if not profile.get("grants_gov_ready"):
        owe("chief", "Grants.gov registration / SF-424 path ready")
    if not profile.get("justgrants_ready"):
        owe("chief", "JustGrants entity ready after SF-424")
    if not profile.get("two_aors"):
        owe(
            "mayor",
            "Two Authorized Representatives assigned in JustGrants: chief and mayor, not a clerk",
        )

    slots = narrative_slots(profile)
    for key, label in SLOT_LABELS.items():
        text = slots.get(key) or ""
        if key == "use_of_funds" and not _present(profile.get("use_of_funds")):
            continue
        if still_has_unresolved_number(text) and key != "use_of_funds":
            notes.append(f"{label} still has a bracketed field that is not sourced.")

    ready = not owed
    return {
        "ready": ready,
        "owed": owed,
        "notes": notes,
        "slots": slots,
        "saa": saa,
        "banner": (
            "Ready to print as a packet. The SAA's official form is still required."
            if ready
            else "INCOMPLETE — not ready to file. Blanks the chief or mayor still owe are listed."
        ),
    }


def slug_agency(name: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9]+", "-", (name or "").strip()).strip("-")
    return cleaned or "Agency"


def packet_filenames(profile: dict[str, Any], when: date | None = None) -> dict[str, str]:
    when = when or date.today()
    stamp = when.isoformat()
    agency = slug_agency(str(profile.get("agency_name") or "Agency"))
    saa = saa_for(str(profile.get("state") or ""))
    st = saa.get("state_abbr") or "State"
    return {
        "jag": f"{agency}_{st}-JAG-Passthrough_{stamp}.pdf",
        "chp": f"{agency}_FY27-CHP-Readiness_{stamp}.pdf",
        "zip": f"{agency}_DutyPacket_{stamp}.zip",
    }


def _wrap(text: str, width: int = 96) -> list[str]:
    words = (text or "").split()
    if not words:
        return [""]
    lines = [""]
    for word in words:
        trial = (lines[-1] + " " + word).strip()
        if len(trial) <= width:
            lines[-1] = trial
        else:
            lines.append(word)
    return lines


class CityHallPDF:
    def __init__(self, buf: io.BytesIO, profile: dict[str, Any], review: dict[str, Any]):
        self.buf = buf
        self.profile = profile
        self.review = review
        self.c = canvas.Canvas(buf, pagesize=letter, pageCompression=0)
        self.width, self.height = letter
        self.page = 0

    def new_page(self, kicker: str) -> None:
        if self.page:
            self.c.showPage()
        self.page += 1
        c = self.c
        c.setFillColor(PAPER)
        c.rect(0, 0, self.width, self.height, fill=1, stroke=0)
        c.setFillColor(NAVY)
        c.rect(0, self.height - 1.15 * inch, self.width, 1.15 * inch, fill=1, stroke=0)
        self._seal(0.55 * inch, self.height - 0.58 * inch, 0.36 * inch)
        c.setFillColor(Color(1, 1, 1))
        c.setFont("Times-Bold", 16)
        agency = self.profile.get("agency_name") or "Municipal Police Department"
        c.drawString(1.1 * inch, self.height - 0.48 * inch, agency)
        c.setFont("Times-Italic", 10)
        c.drawString(1.1 * inch, self.height - 0.70 * inch, kicker)
        c.setFillColor(GOLD)
        c.rect(0, self.height - 1.20 * inch, self.width, 4, fill=1, stroke=0)
        c.setFillColor(NAVY)
        c.rect(0, 0, self.width, 0.42 * inch, fill=1, stroke=0)
        c.setFillColor(Color(1, 1, 1))
        c.setFont("Times-Roman", 8)
        c.drawString(
            0.6 * inch,
            0.18 * inch,
            "Duty Packet — packet and checklist only. Not filed to Grants.gov or JustGrants.",
        )
        c.drawRightString(self.width - 0.6 * inch, 0.18 * inch, f"Page {self.page}")
        if not self.review["ready"]:
            c.saveState()
            c.setFillColor(HexColor("#E8D2D2"))
            c.rect(0, self.height - 1.52 * inch, self.width, 0.30 * inch, fill=1, stroke=0)
            c.setFillColor(WARN)
            c.setFont("Times-Bold", 10)
            c.drawCentredString(
                self.width / 2,
                self.height - 1.42 * inch,
                "INCOMPLETE PACKET — NOT READY TO FILE",
            )
            c.restoreState()
            c.saveState()
            c.translate(self.width / 2, self.height / 2)
            c.rotate(38)
            c.setFillColor(HexColor("#E8C4C4"))
            c.setFont("Times-Bold", 46)
            c.drawCentredString(0, 0, "INCOMPLETE")
            c.restoreState()

    def _seal(self, x: float, y: float, r: float) -> None:
        c = self.c
        c.setStrokeColor(GOLD)
        c.setLineWidth(1.4)
        c.setFillColor(NAVY)
        c.circle(x, y, r, fill=1, stroke=1)
        c.setStrokeColor(CREAM)
        c.setLineWidth(0.6)
        c.circle(x, y, r * 0.78, fill=0, stroke=1)
        c.setFillColor(GOLD)
        c.setFont("Times-Bold", 7)
        initials = "".join(
            part[0] for part in (self.profile.get("agency_name") or "PD").split()[:3]
        ).upper()
        c.drawCentredString(x, y - 2.5, initials or "PD")

    def _body_top(self) -> float:
        return self.height - (1.75 * inch if not self.review["ready"] else 1.48 * inch)

    def heading(self, y: float, text: str) -> float:
        self.c.setFillColor(NAVY)
        self.c.setFont("Times-Bold", 13)
        self.c.drawString(0.7 * inch, y, text)
        self.c.setStrokeColor(GOLD)
        self.c.setLineWidth(0.8)
        self.c.line(0.7 * inch, y - 4, 7.8 * inch, y - 4)
        return y - 22

    def para(self, y: float, text: str, *, italic: bool = False, color: Color | None = None) -> float:
        self.c.setFillColor(color or INK)
        self.c.setFont("Times-Italic" if italic else "Times-Roman", 10)
        for line in _wrap(text, 98):
            if y < 0.7 * inch:
                self.new_page(self._current_kicker)
                y = self._body_top()
            self.c.drawString(0.7 * inch, y, line)
            y -= 13
        return y - 6

    def field(self, y: float, label: str, value: str, *, blank: bool = False) -> float:
        self.c.setFillColor(NAVY)
        self.c.setFont("Times-Bold", 9)
        self.c.drawString(0.7 * inch, y, label.upper())
        y -= 13
        shown = value if value else "—"
        self.c.setFillColor(WARN if blank or not value else INK)
        self.c.setFont("Times-Italic" if blank or not value else "Times-Roman", 10)
        for line in _wrap(shown, 98):
            self.c.drawString(0.7 * inch, y, line)
            y -= 13
        self.c.setStrokeColor(RULE)
        self.c.setLineWidth(0.4)
        self.c.line(0.7 * inch, y + 6, 7.8 * inch, y + 6)
        return y - 4

    def build_jag(self) -> None:
        self._current_kicker = state_packet_title(str(self.profile.get("state") or ""))
        self.new_page(self._current_kicker)
        y = self._body_top()
        saa = self.review["saa"]
        y = self.heading(y, "Letter of transmittal")
        y = self.para(
            y,
            "To the State Administering Agency named below. This is a municipal packet "
            "for a local JAG pass-through. It is not a direct federal JAG application.",
        )
        y = self.field(y, "State administering agency", saa.get("saa") or "")
        y = self.field(y, "Program", saa.get("program") or "")
        y = self.field(y, "SAA site (confirm the current solicitation here)", saa.get("url") or "")
        y = self.field(y, "Application system", saa.get("portal") or "")
        y = self.para(y, saa.get("direct_floor_note") or "", italic=True)
        y = self.para(y, saa.get("form_warning") or "", italic=True, color=WARN)

        y = self.heading(y - 4, "Agency profile")
        y = self.field(y, "Agency", str(self.profile.get("agency_name") or ""), blank=not self.profile.get("agency_name"))
        y = self.field(y, "ORI", str(self.profile.get("ori") or ""), blank=not self.profile.get("ori"))
        y = self.field(
            y,
            "Town / state",
            f"{self.profile.get('town') or '—'}, {self.profile.get('state') or '—'}",
            blank=not (self.profile.get("town") and self.profile.get("state")),
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
        crime_text = crime.get("citation") or crime.get("blank_reason") or ""
        y = self.field(
            y,
            "Crime (FBI CDE, this ORI only)",
            crime_text,
            blank=not crime.get("ok"),
        )
        y = self.field(y, "Chief", str(self.profile.get("chief_name") or ""), blank=not self.profile.get("chief_name"))
        y = self.field(y, "Mayor", str(self.profile.get("mayor_name") or ""), blank=not self.profile.get("mayor_name"))

        self.new_page(self._current_kicker)
        y = self._body_top()
        y = self.heading(y, "Narrative frames")
        y = self.para(
            y,
            "Written in the chief's voice. Brackets stay until the sourced field is on this packet. "
            "No sample town is supplied.",
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

        self.new_page("Filing checklist — one page")
        y = self._body_top()
        y = self.heading(y, "One-page filing checklist")
        y = self.para(
            y,
            "Order of filing: SAM.gov current, then Grants.gov SF-424, then JustGrants. "
            "COPS awards need two Authorized Representatives: the chief and the mayor. A clerk is not enough.",
        )
        checks = [
            (
                "SAM.gov",
                "Registration current. Unique Entity ID on file. Annual notarized Entity Administrator letter on file.",
                bool(self.profile.get("sam_current") and self.profile.get("uei")),
            ),
            (
                "Grants.gov",
                "Workspace ready for SF-424 when a federal notice is open. This packet does not submit the form.",
                bool(self.profile.get("grants_gov_ready")),
            ),
            (
                "JustGrants",
                "Entity available after SF-424. Two Authorized Representatives: chief and mayor.",
                bool(self.profile.get("justgrants_ready") and self.profile.get("two_aors")),
            ),
            (
                "State SAA",
                f"Current {saa.get('state') or 'state'} JAG local solicitation confirmed on the SAA site. Live windows are owned outside this app.",
                bool(self.profile.get("saa_solicitation_confirmed")),
            ),
            (
                "COPS Authorized Representatives",
                f"Chief: {self.profile.get('chief_name') or '[chief]'}. Mayor: {self.profile.get('mayor_name') or '[mayor]'}. Not a clerk.",
                bool(self.profile.get("chief_name") and self.profile.get("mayor_name") and self.profile.get("two_aors")),
            ),
        ]
        for title, detail, done in checks:
            mark = "[X]" if done else "[ ]"
            y = self.para(y, f"{mark}  {title} — {detail}", color=INK if done else WARN)

        y = self.heading(y, "Items still owed")
        if self.review["ready"]:
            y = self.para(y, "No blanks remain for the chief or mayor on this packet.")
        else:
            for item in self.review["owed"]:
                y = self.para(y, f"• {item['who'].title()} still owes: {item['item']}", color=WARN)
            for note in self.review["notes"]:
                y = self.para(y, f"• {note}", italic=True)
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
            "print a deadline. When a window opens, it is tracked outside this app.",
        )
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
        y = self.field(
            y,
            "Chief's answer (match or waiver)",
            match,
            blank=not match,
        )

        retention = str(self.profile.get("chp_retention") or "").strip()
        y = self.heading(y, "Twelve-month post-grant retention")
        y = self.para(
            y,
            "Each CHP-funded position must be kept for at least 12 months after federal funding "
            "for that position ends, added to the local budget, not absorbed by attrition. "
            "This line stays blank until the chief answers.",
        )
        y = self.field(
            y,
            "Chief's answer (retention)",
            retention,
            blank=not retention,
        )

        y = self.heading(y, "Authorized Representatives — not a clerk")
        y = self.field(
            y,
            "Top law-enforcement executive (chief)",
            str(self.profile.get("chief_name") or ""),
            blank=not self.profile.get("chief_name"),
        )
        y = self.field(
            y,
            "Top government executive (mayor)",
            str(self.profile.get("mayor_name") or ""),
            blank=not self.profile.get("mayor_name"),
        )
        y = self.para(
            y,
            "COPS awards require both people as Authorized Representatives in JustGrants. "
            "A clerk, secretary, or trustee is not an acceptable Authorized Representative.",
            italic=True,
        )

        pop = self.profile.get("population") or {}
        crime = self.profile.get("crime") or {}
        y = self.heading(y, "Sourced figures already on the packet")
        y = self.field(
            y,
            "Population",
            pop.get("citation") or pop.get("blank_reason") or "[sourced population]",
            blank=not pop.get("ok"),
        )
        y = self.field(
            y,
            "Crime",
            crime.get("citation") or crime.get("blank_reason") or "[sourced crime]",
            blank=not crime.get("ok"),
        )
        y = self.heading(y, "Items still owed")
        chp_owed = [
            item
            for item in self.review["owed"]
            if "CHP" in item["item"] or "Authorized" in item["item"] or item["who"] in {"chief", "mayor"}
        ]
        if self.review["ready"]:
            y = self.para(y, "No blanks remain on the readiness sheet.")
        else:
            for item in chp_owed:
                y = self.para(y, f"• {item['who'].title()} still owes: {item['item']}", color=WARN)
        self.c.save()


def render_jag_pdf(profile: dict[str, Any], review: dict[str, Any] | None = None) -> bytes:
    review = review or completeness(profile)
    buf = io.BytesIO()
    CityHallPDF(buf, profile, review).build_jag()
    return buf.getvalue()


def render_chp_pdf(profile: dict[str, Any], review: dict[str, Any] | None = None) -> bytes:
    review = review or completeness(profile)
    buf = io.BytesIO()
    CityHallPDF(buf, profile, review).build_chp()
    return buf.getvalue()


def render_zip(profile: dict[str, Any], when: date | None = None) -> tuple[str, bytes]:
    review = completeness(profile)
    names = packet_filenames(profile, when)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(names["jag"], render_jag_pdf(profile, review))
        zf.writestr(names["chp"], render_chp_pdf(profile, review))
    return names["zip"], buf.getvalue()
