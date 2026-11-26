"""Fill in Mauna's Mac App Store listing through the App Store Connect API.

Adapted from Night Train's tool: platform MAC_OS, desktop screenshots, two in-app purchases
(Mauna Pro and the $0 7-day trial), and a step that registers the bundle ID.

Safe to run again: each step looks before it writes. Nothing is submitted for review unless the
"submit" step is named on its own (it is never part of "all").

usage:
  ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_….p8 \
  python asc.py [bundleid|check|all|appinfo|version|screenshots|review|build|iap|update|submit]
                [--contact "First Last" "+1 555…" email | --contact-from com.narasimhadixit.nighttrain]

  bundleid: registers in.throttlelabs.mauna for macOS if it isn't already (works before the app exists).
  Prices come from listing.json ("iaps"). Apple doesn't let the API create the app record itself:
  do that once on the website (Apps › + › New App), then run "all".

  update: for a new version of a live app: creates the version, sets What's New, carries the
          App Review contact over from the last version with the current notes, selects the
          build and turns phased release off.
  submit: sends the editable version for App Review.

The key file is read from disk and only used to sign short-lived tokens for api.appstoreconnect.apple.com.
Apple's App Privacy questionnaire is not in the API; it's done once on the website.
"""
import hashlib
import json
import os
import re
import sys
import time

import jwt
import requests

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
API = "https://api.appstoreconnect.apple.com"
CFG = json.load(open(os.path.join(HERE, "listing.json")))


# ---------------------------------------------------------------------------------------------
# HTTP

def token():
    key = open(os.path.expanduser(os.environ["ASC_KEY_PATH"])).read()
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


_TOKEN = None


def call(method, path, body=None, params=None, ok=(200, 201, 204)):
    global _TOKEN
    _TOKEN = _TOKEN or token()
    r = requests.request(method, API + path, json=body, params=params,
                         headers={"Authorization": f"Bearer {_TOKEN}", "Content-Type": "application/json"}, timeout=60)
    if r.status_code not in ok:
        raise SystemExit(f"{method} {path} → {r.status_code}\n{r.text[:1500]}")
    return r.json() if r.text else {}


def get(path, **params):
    return call("GET", path, params=params or None)


def say(*a):
    print("·", *a, flush=True)


def paragraphs(text):
    """Join hard-wrapped lines into paragraphs; keep bullets and numbered steps on their own lines."""
    out = []
    for line in text.strip().split("\n"):
        s = line.strip()
        starts_item = re.match(r"^(•|-|\d+\.)\s", s) or s.isupper() or s == ""
        if out and out[-1] != "" and not starts_item and s:
            out[-1] += " " + s
        else:
            out.append(s)
    return re.sub(r"\n{3,}", "\n\n", "\n".join(out)).strip()


# ---------------------------------------------------------------------------------------------
# Lookups

def app():
    apps = get("/v1/apps", **{"filter[bundleId]": CFG["bundleId"]})["data"]
    if not apps:
        raise SystemExit(f"No app with bundle ID {CFG['bundleId']} in App Store Connect.")
    return apps[0]


def editable_version(app_id, create=True):
    vs = get(f"/v1/apps/{app_id}/appStoreVersions", **{"filter[platform]": "MAC_OS", "limit": 10})["data"]
    editable = [v for v in vs if v["attributes"]["appStoreState"] in
                ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")]
    if editable:
        v = editable[0]
        if v["attributes"]["versionString"] != CFG["version"]:
            v = call("PATCH", f"/v1/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"],
                     "attributes": {"versionString": CFG["version"]}}})["data"]
        return v
    if not create:
        return None
    return call("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions",
                "attributes": {"platform": "MAC_OS", "versionString": CFG["version"]},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]


def version_localization(version_id):
    locs = get(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")["data"]
    loc = next((l for l in locs if l["attributes"]["locale"] == CFG["locale"]), None)
    if loc:
        return loc
    return call("POST", "/v1/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations",
                "attributes": {"locale": CFG["locale"]},
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})["data"]


# ---------------------------------------------------------------------------------------------
# Steps

def step_bundleid():
    found = get("/v1/bundleIds", **{"filter[identifier]": CFG["bundleId"]})["data"]
    exact = [b for b in found if b["attributes"]["identifier"] == CFG["bundleId"]]
    if exact:
        say("Bundle ID already registered:", CFG["bundleId"], exact[0]["attributes"]["platform"])
        return
    call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": CFG["bundleId"], "name": CFG["appInfo"]["name"].split(":")[0], "platform": "MAC_OS"}}})
    say("Bundle ID registered:", CFG["bundleId"], "(macOS)")


def step_check(a):
    say("App:", a["attributes"]["name"], a["id"], a["attributes"]["primaryLocale"])
    for v in get(f"/v1/apps/{a['id']}/appStoreVersions", **{"limit": 5})["data"]:
        say("Version", v["attributes"]["versionString"], v["attributes"]["appStoreState"])
    for b in get("/v1/builds", **{"filter[app]": a["id"], "sort": "-uploadedDate", "limit": 5,
                                  "include": "preReleaseVersion"})["data"]:
        say("Build", b["attributes"]["version"], b["attributes"]["processingState"], b["attributes"]["uploadedDate"][:16])
    for p in get(f"/v1/apps/{a['id']}/inAppPurchasesV2")["data"]:
        say("IAP", p["attributes"]["productId"], p["attributes"]["state"])


def step_appinfo(a):
    infos = get(f"/v1/apps/{a['id']}/appInfos")["data"]
    info = next((i for i in infos if i["attributes"].get("appStoreState") in
                 ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", None)), infos[0])
    c = CFG["appInfo"]
    call("PATCH", f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": c["primaryCategory"]}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": c["secondaryCategory"]}}}}})
    say("Categories:", c["primaryCategory"], "/", c["secondaryCategory"])
    locs = get(f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]
    loc = next((l for l in locs if l["attributes"]["locale"] == CFG["locale"]), locs[0])
    call("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"],
         "attributes": {"name": c["name"], "subtitle": c["subtitle"], "privacyPolicyUrl": c["privacyPolicyUrl"]}}})
    say("Name, subtitle, privacy policy URL")
    # Age rating: no objectionable content. Every "how often" answer None, every yes/no answer No.
    decl = get(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    attrs = {}
    for k, v in decl["attributes"].items():
        if isinstance(v, bool) or v is None and k.startswith(("is", "has", "contains", "unrestricted", "lootBox", "advertising", "ageAssurance", "parental", "messaging", "userGenerated", "healthOrWellness")):
            attrs[k] = False
        elif isinstance(v, str) or v is None:
            attrs[k] = "NONE"
    # Only the content questions: leave overrides, Korea's GRAC number, kids band and URLs alone.
    for k in list(attrs):
        if k == "kidsAgeBand" or "Override" in k or "grac" in k.lower() or k.endswith("Url"):
            attrs.pop(k)
    # Apple adds questions over time; where a guess was the wrong type, its error names the field.
    for _ in range(4):
        global _TOKEN
        _TOKEN = _TOKEN or token()
        r = requests.patch(f"{API}/v1/ageRatingDeclarations/{decl['id']}", timeout=60,
                           headers={"Authorization": f"Bearer {_TOKEN}", "Content-Type": "application/json"},
                           json={"data": {"type": "ageRatingDeclarations", "id": decl["id"], "attributes": attrs}})
        if r.status_code < 300:
            break
        errs = r.json().get("errors", [])
        fixable = [e for e in errs if e.get("code") == "ENTITY_ERROR.ATTRIBUTE.TYPE"]
        if not fixable:
            raise SystemExit(f"Age rating → {r.status_code}\n{r.text[:1200]}")
        for e in fixable:
            k = e["source"]["pointer"].split("/")[-1]
            attrs[k] = False if "BOOLEAN" in e["detail"] else "NONE"
    else:
        raise SystemExit("Age rating: could not settle the answers")
    say("Age rating: no objectionable content")


def step_version(a):
    v = editable_version(a["id"])
    say("Version", v["attributes"]["versionString"], v["attributes"]["appStoreState"])
    call("PATCH", f"/v1/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"],
         "attributes": {"copyright": f"{time.gmtime().tm_year} Narasimha Dixit"}}})
    loc = version_localization(v["id"])
    c = CFG["version_localization"]
    desc = paragraphs(open(os.path.join(HERE, c["descriptionFile"])).read())
    call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
         "attributes": {"description": desc, "keywords": c["keywords"], "promotionalText": c["promotionalText"],
                        "supportUrl": c["supportUrl"], "marketingUrl": c["marketingUrl"]}}})
    say("Description, keywords, promo text, support and marketing URLs")
    # The app is free to download, in every territory.
    if not get(f"/v1/apps/{a['id']}/appPriceSchedule", ).get("data"):
        pass
    try:
        get(f"/v1/apps/{a['id']}/appPriceSchedule/manualPrices")
        has_price = bool(get(f"/v1/apps/{a['id']}/appPriceSchedule/manualPrices")["data"])
    except SystemExit:
        has_price = False
    if not has_price:
        free = next(p for p in get(f"/v1/apps/{a['id']}/appPricePoints", **{"filter[territory]": "USA", "limit": 200})["data"]
                    if float(p["attributes"]["customerPrice"]) == 0)
        call("POST", "/v1/appPriceSchedules", {"data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": a["id"]}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]}}},
            "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}}}]})
        say("Price: free")
    return v


def upload(create_path, create_body, patch_type, path):
    """Reserve an asset, upload its parts, then commit it with its checksum."""
    data = open(path, "rb").read()
    res = call("POST", create_path, create_body)["data"]
    for op in res["attributes"]["uploadOperations"]:
        part = data[op["offset"]: op["offset"] + op["length"]]
        r = requests.request(op["method"], op["url"], data=part, headers={h["name"]: h["value"] for h in op["requestHeaders"]}, timeout=120)
        if r.status_code >= 300:
            raise SystemExit(f"upload part → {r.status_code} {r.text[:300]}")
    call("PATCH", f"{create_path}/{res['id']}", {"data": {"type": patch_type, "id": res["id"],
         "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    return res["id"]


def step_screenshots(a):
    v = editable_version(a["id"])
    loc = version_localization(v["id"])
    want = CFG["screenshots"]["displayType"]
    sets = get(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
    s = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == want), None)
    if s:
        for old in get(f"/v1/appScreenshotSets/{s['id']}/appScreenshots")["data"]:
            call("DELETE", f"/v1/appScreenshots/{old['id']}")
    else:
        s = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": want},
                 "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]
    for f in CFG["screenshots"]["files"]:
        p = os.path.join(ROOT, f)
        upload("/v1/appScreenshots", {"data": {"type": "appScreenshots",
               "attributes": {"fileName": os.path.basename(p), "fileSize": os.path.getsize(p)},
               "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": s["id"]}}}}}, "appScreenshots", p)
        say("Screenshot", os.path.basename(p))


def step_review(a, contact):
    v = editable_version(a["id"])
    notes = paragraphs(open(os.path.join(HERE, CFG["review"]["notesFile"])).read())
    first, last, phone, email = contact
    attrs = {"contactFirstName": first, "contactLastName": last, "contactPhone": phone, "contactEmail": email,
             "demoAccountRequired": False, "notes": notes}
    existing = get(f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail").get("data")
    if existing:
        call("PATCH", f"/v1/appStoreReviewDetails/{existing['id']}", {"data": {"type": "appStoreReviewDetails", "id": existing["id"], "attributes": attrs}})
    else:
        call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
             "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    say("App Review notes and contact; no sign-in required")


def step_build(a):
    v = editable_version(a["id"])
    builds = get("/v1/builds", **{"filter[app]": a["id"], "filter[version]": CFG["build"],
                                  "filter[preReleaseVersion.version]": CFG["version"]})["data"]
    if not builds:
        raise SystemExit(f"Build {CFG['build']} ({CFG['version']}) isn't in App Store Connect yet (still uploading or processing).")
    b = builds[0]
    if b["attributes"]["processingState"] != "VALID":
        raise SystemExit(f"Build {CFG['build']} is still {b['attributes']['processingState']}; run this step again in a few minutes.")
    call("PATCH", f"/v1/appStoreVersions/{v['id']}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
    say("Build", CFG["build"], "selected for version", CFG["version"])


def step_update(a):
    v = editable_version(a["id"])
    say("Version", v["attributes"]["versionString"], v["attributes"]["appStoreState"])
    loc = version_localization(v["id"])
    call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
         "attributes": {"whatsNew": CFG["version_localization"]["whatsNew"]}}})
    say("What's New")
    # App Review: the contact from the last version that had one, with this version's notes.
    notes = paragraphs(open(os.path.join(HERE, CFG["review"]["notesFile"])).read())
    attrs = {"demoAccountRequired": False, "notes": notes}
    for old in get(f"/v1/apps/{a['id']}/appStoreVersions", **{"filter[platform]": "MAC_OS", "limit": 10})["data"]:
        if old["id"] == v["id"]:
            continue
        d = get(f"/v1/appStoreVersions/{old['id']}/appStoreReviewDetail").get("data")
        if d:
            for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail"):
                attrs[k] = d["attributes"].get(k)
            break
    existing = get(f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail").get("data")
    if existing:
        call("PATCH", f"/v1/appStoreReviewDetails/{existing['id']}", {"data": {"type": "appStoreReviewDetails", "id": existing["id"], "attributes": attrs}})
    else:
        call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
             "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    say("App Review notes", "(contact carried over)" if "contactEmail" in attrs else "(no earlier contact found)")
    step_build(a)
    # Everyone gets the update straight away: no phased release.
    phased = get(f"/v1/appStoreVersions/{v['id']}/appStoreVersionPhasedRelease").get("data")
    if phased:
        call("DELETE", f"/v1/appStoreVersionPhasedReleases/{phased['id']}")
        say("Phased release: off (removed)")
    else:
        say("Phased release: off")
    # Release as soon as Apple approves.
    call("PATCH", f"/v1/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"],
         "attributes": {"releaseType": "AFTER_APPROVAL"}}})
    say("Release: automatically after approval")


def step_submit(a):
    v = editable_version(a["id"], create=False)
    if not v:
        raise SystemExit("No editable version to submit.")
    sub = call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "MAC_OS"},
               "relationships": {"app": {"data": {"type": "apps", "id": a["id"]}}}}})["data"]
    call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
         "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
         "appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    call("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"],
         "attributes": {"submitted": True}}})
    say("Submitted version", v["attributes"]["versionString"], "for App Review")


def step_iap(a, _=None):
    for c in CFG["iaps"]:
        iap_one(a, c, c.get("price"))


def iap_one(a, c, price):
    existing = [p for p in get(f"/v1/apps/{a['id']}/inAppPurchasesV2", **{"filter[productId]": c["productId"]})["data"]]
    if existing:
        iap = existing[0]
        say("IAP exists:", c["productId"], iap["attributes"]["state"])
    else:
        iap = call("POST", "/v2/inAppPurchases", {"data": {"type": "inAppPurchases", "attributes": {
            "name": c["referenceName"], "productId": c["productId"], "inAppPurchaseType": c["type"],
            "reviewNote": c["reviewNote"], "familySharable": c["familySharable"]},
            "relationships": {"app": {"data": {"type": "apps", "id": a["id"]}}}}})["data"]
        say("IAP created:", c["productId"])
    # Display name and description
    locs = get(f"/v2/inAppPurchases/{iap['id']}/inAppPurchaseLocalizations")["data"]
    attrs = {"name": c["displayName"], "description": c["description"]}
    loc = next((l for l in locs if l["attributes"]["locale"] == CFG["locale"]), None)
    if loc:
        call("PATCH", f"/v1/inAppPurchaseLocalizations/{loc['id']}", {"data": {"type": "inAppPurchaseLocalizations", "id": loc["id"], "attributes": attrs}})
    else:
        call("POST", "/v1/inAppPurchaseLocalizations", {"data": {"type": "inAppPurchaseLocalizations", "attributes": {**attrs, "locale": CFG["locale"]},
             "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap["id"]}}}}})
    say("IAP name and description")
    # Price: set in USD; Apple fills every other territory from it.
    if price is not None:
        points, nxt = [], f"/v2/inAppPurchases/{iap['id']}/pricePoints"
        params = {"filter[territory]": "USA", "limit": 200}
        while nxt:
            page = call("GET", nxt.replace(API, ""), params=params)
            points += page["data"]
            nxt, params = page.get("links", {}).get("next"), None
        pt = next((p for p in points if abs(float(p["attributes"]["customerPrice"]) - price) < 0.001), None)
        if not pt:
            near = sorted({float(p["attributes"]["customerPrice"]) for p in points}, key=lambda x: abs(x - price))[:5]
            raise SystemExit(f"No USD price point at {price}. Nearest: {near}")
        call("POST", "/v1/inAppPurchasePriceSchedules", {"data": {"type": "inAppPurchasePriceSchedules", "relationships": {
            "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap["id"]}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price}"}]}}},
            "included": [{"type": "inAppPurchasePrices", "id": "${price}", "attributes": {"startDate": None},
                          "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": pt["id"]}}}}]})
        say(f"IAP price: ${price:.2f} (USD base; other countries set by Apple)")
    # Available everywhere the app is.
    try:
        territories = [t["id"] for t in get("/v1/territories", limit=200)["data"]]
        call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {"type": "inAppPurchaseAvailabilities",
             "attributes": {"availableInNewTerritories": True}, "relationships": {
             "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap["id"]}},
             "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}}, ok=(201, 409))
        say("IAP available in all territories")
    except SystemExit as e:
        say("IAP availability not set:", str(e)[:200])
    # Review screenshot
    shot = get(f"/v2/inAppPurchases/{iap['id']}/appStoreReviewScreenshot").get("data")
    if shot and (shot["attributes"].get("assetDeliveryState") or {}).get("state") == "FAILED":
        # Apple rejected it (for a Mac app it must be a Mac screenshot size, e.g. 2880×1800): replace it.
        call("DELETE", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{shot['id']}")
        shot = None
    if not shot:
        p = os.path.join(ROOT, c["reviewScreenshot"])
        upload("/v1/inAppPurchaseAppStoreReviewScreenshots", {"data": {"type": "inAppPurchaseAppStoreReviewScreenshots",
               "attributes": {"fileName": os.path.basename(p), "fileSize": os.path.getsize(p)},
               "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap["id"]}}}}},
               "inAppPurchaseAppStoreReviewScreenshots", p)
        say("IAP review screenshot")


if __name__ == "__main__":
    args = sys.argv[1:]
    what = args[0] if args else "check"
    price = float(args[args.index("--price") + 1]) if "--price" in args else None
    contact = None
    if "--contact" in args:
        i = args.index("--contact")
        name, phone, email = args[i + 1], args[i + 2], args[i + 3]
        first, _, last = name.partition(" ")
        contact = (first, last or first, phone, email)
    if what == "bundleid":
        step_bundleid()
        sys.exit(0)
    a = app()
    if "--contact-from" in args:
        # The App Review contact from another of your apps (its latest version that has one).
        other_id = args[args.index("--contact-from") + 1]
        other = get("/v1/apps", **{"filter[bundleId]": other_id})["data"]
        if not other:
            raise SystemExit(f"No app with bundle ID {other_id}")
        for v in get(f"/v1/apps/{other[0]['id']}/appStoreVersions", limit=10)["data"]:
            d = get(f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail").get("data")
            if d and d["attributes"].get("contactEmail"):
                at = d["attributes"]
                contact = (at["contactFirstName"], at["contactLastName"], at["contactPhone"], at["contactEmail"])
                say("App Review contact copied from", other[0]["attributes"]["name"])
                break
        else:
            raise SystemExit(f"{other_id} has no App Review contact to copy")
    if what == "check":
        step_check(a)
    steps = {"appinfo": lambda: step_appinfo(a), "version": lambda: step_version(a),
             "screenshots": lambda: step_screenshots(a), "review": lambda: step_review(a, contact),
             "build": lambda: step_build(a), "iap": lambda: step_iap(a, price)}
    if what == "update":
        step_update(a)
    if what == "submit":
        step_submit(a)
        print("Done.")
        sys.exit(0)
    for name in (steps if what == "all" else [what] if what in steps else []):
        if name == "review" and not contact:
            say("Skipping review details: pass --contact \"First Last\" \"+phone\" email")
            continue
        steps[name]()
    print("Done. Nothing was submitted by this run.")
