#!/usr/bin/env python3
"""Automated review for phase-2 metadata. This IS the review — 50 locales
cannot be human-checked. Exit 1 on any hard failure."""
import os, sys, unicodedata

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "metadata")
LOCALES = """ar-SA bn-BD ca cs da de-DE el en-AU en-CA en-GB en-US es-ES es-MX
fi fr-CA fr-FR gu-IN he hi hr hu id it ja kn-IN ko ml-IN mr-IN ms nl-NL no
or-IN pa-IN pl pt-BR pt-PT ro ru sk sl-SI sv ta-IN te-IN th tr uk ur-PK vi
zh-Hans zh-Hant""".split()
LIMITS = {"name":30,"subtitle":30,"keywords":100,"promotional_text":170,"description":4000}
URLS = ["https://convotrack.in/privacy","https://convotrack.in/terms"]
BIDI = {0x200E,0x200F,0x202A,0x202B,0x202C,0x202D,0x202E}
LATIN = set("""ca cs da de-DE en-AU en-CA en-GB en-US es-ES es-MX fi fr-CA
fr-FR hr hu id it ms nl-NL no pl pt-BR pt-PT ro sk sl-SI sv tr vi""".split())

fails, warns = [], []
def fail(m): fails.append(m)
def warn(m): warns.append(m)

src = {f: open(f"{ROOT}/en-US/{f}.txt").read().strip() for f in LIMITS}
present = []
for loc in LOCALES:
    d = f"{ROOT}/{loc}"
    if not os.path.isdir(d):
        fail(f"{loc}: MISSING directory"); continue
    present.append(loc)
    for f, lim in LIMITS.items():
        p = f"{d}/{f}.txt"
        if not os.path.exists(p): fail(f"{loc}/{f}.txt: MISSING"); continue
        t = open(p, encoding="utf-8").read().strip()
        n = len(t)                                   # CHARACTERS, not bytes
        if n == 0: fail(f"{loc}/{f}: EMPTY")
        elif n > lim: fail(f"{loc}/{f}: {n}/{lim} OVER by {n-lim}")
        if loc != "en-US" and t == src[f] and f in ("name","subtitle","keywords","description"):
            warn(f"{loc}/{f}: identical to en-US (untranslated?)")
        if any(ord(c) in BIDI for c in t): fail(f"{loc}/{f}: contains bidi control chars")
    # verbatim atoms
    for u in URLS:
        dp = f"{d}/description.txt"
        if os.path.exists(dp) and u not in open(dp, encoding="utf-8").read():
            fail(f"{loc}/description: verbatim URL missing/mangled -> {u}")
    for f, want in (("privacy_url","https://convotrack.in/privacy"),
                    ("marketing_url","https://convotrack.in"),
                    ("support_url","https://convotrack.in")):
        p = f"{d}/{f}.txt"
        if not os.path.exists(p): fail(f"{loc}/{f}.txt: MISSING (per-locale privacy URL is required at submit)")
        elif open(p, encoding="utf-8").read().strip() != want: fail(f"{loc}/{f}: != {want}")
    # keyword hygiene
    kp = f"{d}/keywords.txt"
    if os.path.exists(kp):
        k = open(kp, encoding="utf-8").read().strip()
        if ", " in k: warn(f"{loc}/keywords: space after comma wastes chars")
        parts = [x.strip() for x in k.split(",") if x.strip()]
        if len(parts) != len(set(parts)): fail(f"{loc}/keywords: duplicate phrase")
    # brand shape
    np_ = f"{d}/name.txt"
    if os.path.exists(np_):
        nm = open(np_, encoding="utf-8").read().strip()
        if loc in LATIN and "ConvoTrack" not in nm:
            fail(f"{loc}/name: BrandWord 'ConvoTrack' missing from Latin-script locale -> {nm}")
        if loc not in LATIN and loc != "en-US" and "ConvoTrack" in nm:
            warn(f"{loc}/name: brand left in Latin script, expected transliteration -> {nm}")

print(f"locales present: {len(present)}/{len(LOCALES)}")
for w in warns: print("WARN", w)
for f in fails: print("FAIL", f)
print(f"\n{len(fails)} failures, {len(warns)} warnings")
sys.exit(1 if fails else 0)
