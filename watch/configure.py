#!/usr/bin/env python3
"""Writes secrets/config.xml for the Garmin watch app.

Asks for your Homebridge address and login, finds the airco's services and
stores everything in watch/secrets/config.xml (git-ignored). The password is
only sent to your own Homebridge and written to that local file.
"""
import getpass
import json
import os
import sys
import urllib.request
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "secrets", "config.xml")


def request(url, data=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, headers=headers, method="POST" if body is not None else "GET")
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read() or b"null")


def main():
    url = input("Homebridge address (https://...): ").strip().rstrip("/")
    if "://" not in url:
        url = "https://" + url
    user = input("Username (empty if no login): ").strip()
    password = getpass.getpass("Password (hidden): ") if user else ""

    try:
        if user:
            token = request(url + "/api/auth/login", {"username": user, "password": password})["access_token"]
        else:
            token = request(url + "/api/auth/noauth", {})["access_token"]
        services = request(url + "/api/accessories", token=token)
    except Exception as e:  # noqa: BLE001
        sys.exit(f"Could not log in or read accessories: {e}")

    def writable(s, t):
        return any(c.get("type") == t and c.get("canWrite") for c in s.get("serviceCharacteristics", []))

    mains = [s for s in services if writable(s, "TargetHeaterCoolerState")]
    if not mains:
        sys.exit("No Heater Cooler service found on this Homebridge.")
    main_svc = mains[0]
    name = main_svc.get("serviceName", "")
    base = name[: -len(" Heater Cooler")] if name.endswith(" Heater Cooler") else name

    def find(suffix):
        want = (base + " " + suffix).lower()
        for s in services:
            if s.get("serviceName", "").lower() == want:
                return s["uniqueId"]
        return ""

    ids = {
        "idMain": main_svc["uniqueId"],
        "idDry": find("Dry Mode Switch"),
        "idFanMode": find("Fan Mode Switch"),
        "idAutoFan": find("Auto Fan Speed Switch"),
    }
    props = {"hbUrl": url, "hbUser": user, "hbPass": password, **ids}

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    lines = ["<resources>", "    <properties>"]
    for k, v in props.items():
        lines.append(f'        <property id="{k}" type="string">{escape(v)}</property>')
    lines += ["    </properties>", "</resources>", ""]
    fd = os.open(OUT, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(lines))

    print(f"\nAirco: {name}")
    for k, v in ids.items():
        print(f"  {k:10} {'found' if v else 'not found'}")
    print(f"Saved to {OUT}")


if __name__ == "__main__":
    main()
