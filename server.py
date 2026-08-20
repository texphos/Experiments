"""Duty Packet — local grant-packet desk. Does not file Grants.gov or JustGrants."""

from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv
from flask import Flask, jsonify, request, send_file, send_from_directory

from duty_packet import completeness, packet_filenames, render_chp_pdf, render_jag_pdf, render_zip
from duty_saa import list_states, saa_for
from duty_sources import keys_status, lookup_acs5_population, lookup_cde_crime

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env")

app = Flask(__name__, static_folder=None)
OUT = ROOT / "packets"
OUT.mkdir(exist_ok=True)


def _json() -> dict:
    payload = request.get_json(silent=True)
    return payload if isinstance(payload, dict) else {}


@app.get("/")
def index():
    return send_from_directory(ROOT, "index.html")


@app.get("/api/status")
def status():
    return jsonify(
        {
            "app": "Duty Packet",
            "files_only": True,
            "submits_grants_gov": False,
            "submits_justgrants": False,
            "scrapes_cops": False,
            "hardcoded_deadlines": False,
            "keys": keys_status(),
            "states": list_states(),
        }
    )


@app.get("/api/saa")
def saa():
    return jsonify(saa_for(request.args.get("state") or ""))


@app.post("/api/population")
def population():
    body = _json()
    result = lookup_acs5_population(str(body.get("town") or ""), str(body.get("state") or ""))
    return jsonify(result)


@app.post("/api/crime")
def crime():
    body = _json()
    result = lookup_cde_crime(str(body.get("ori") or ""))
    return jsonify(result)


@app.post("/api/review")
def review():
    return jsonify(completeness(_json()))


@app.post("/api/packet/jag")
def packet_jag():
    profile = _json()
    names = packet_filenames(profile)
    path = OUT / names["jag"]
    path.write_bytes(render_jag_pdf(profile))
    return send_file(path, as_attachment=True, download_name=names["jag"], mimetype="application/pdf")


@app.post("/api/packet/chp")
def packet_chp():
    profile = _json()
    names = packet_filenames(profile)
    path = OUT / names["chp"]
    path.write_bytes(render_chp_pdf(profile))
    return send_file(path, as_attachment=True, download_name=names["chp"], mimetype="application/pdf")


@app.post("/api/packet/zip")
def packet_zip():
    profile = _json()
    name, data = render_zip(profile)
    path = OUT / name
    path.write_bytes(data)
    return send_file(path, as_attachment=True, download_name=name, mimetype="application/zip")


if __name__ == "__main__":
    host = os.environ.get("DUTY_PACKET_HOST", "127.0.0.1")
    port = int(os.environ.get("DUTY_PACKET_PORT", "8765"))
    print("Duty Packet — packet and checklist only. Nothing is filed.")
    print(f"Open http://{host}:{port}")
    app.run(host=host, port=port, debug=False)
