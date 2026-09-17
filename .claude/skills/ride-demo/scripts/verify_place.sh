#!/bin/bash
# verify_place.sh "<query>" [lat] [lng]
#   ALWAYS run this before typing a start/destination into Create Ride.
#   The in-app field uses Google Places Autocomplete; obscure village names
#   silently resolve to a different town (e.g. "Kanavepura" -> "Kanakapura", 93 km away).
#   Prints what the app's FIRST suggestion will be, and its coordinates.
KEY="${GOOGLE_MAPS_KEY:-$(grep -o 'AIza[A-Za-z0-9_-]*' "$(dirname "${BASH_SOURCE[0]}")/../../../../convotrack/Services/GoogleMapsConfig.swift" | head -1)}"
Q="$1"; LAT="${2:-13.3595}"; LNG="${3:-77.6655}"
ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$Q")
curl -s "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$ENC&location=$LAT,$LNG&radius=8000&key=$KEY" \
| python3 -c "
import json,sys
d=json.load(sys.stdin)
if d.get('status')!='OK': print('  ',d.get('status'),d.get('error_message','')); raise SystemExit(1)
for i,p in enumerate(d['predictions'][:4]):
    print(('  -> FIRST: ' if i==0 else '          ')+p['description'])
"
