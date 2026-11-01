#!/usr/bin/env python3
"""Keep Picnest/Localizable.xcstrings in step with the strings in the Swift code.

xcodebuild does not update the catalog (only the Xcode app does). Each build writes the strings of
each Swift file to *.stringsdata files. This script reads them.

  python3 -I scripts/sync-string-catalog.py           add new keys (no vi yet), mark unused keys stale
  python3 -I scripts/sync-string-catalog.py --check   change nothing, exit 1 if the catalog differs

Build the app first: xcodebuild build -project Picnest.xcodeproj -scheme Picnest -destination 'platform=macOS'
"""
import glob, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "Picnest/Localizable.xcstrings")


def extracted_keys():
    out = subprocess.run(
        ["xcodebuild", "-project", "Picnest.xcodeproj", "-scheme", "Picnest", "-showBuildSettings"],
        cwd=ROOT, capture_output=True, text=True, check=True).stdout
    temp = re.search(r"^\s*TARGET_TEMP_DIR = (.+)$", out, re.M).group(1)
    files = glob.glob(os.path.join(temp, "Objects-normal", "*", "*.stringsdata"))
    if not files:
        sys.exit("No .stringsdata files in %s. Build the app first." % temp)
    keys = set()
    for path in files:
        with open(path, encoding="utf-8") as f:
            keys.update(e["key"] for e in json.load(f)["tables"].get("Localizable", []))
    return keys


def main():
    check = "--check" in sys.argv[1:]
    with open(CATALOG, encoding="utf-8") as f:
        catalog = json.load(f)
    strings = catalog["strings"]
    keys = extracted_keys()
    new = sorted(keys - strings.keys())
    unused = sorted(k for k in strings.keys() - keys if strings[k].get("extractionState") != "stale")
    if check:
        for k in new:
            print("missing from the catalog:", k)
        for k in unused:
            print("not in the code any more:", k)
        sys.exit(1 if new or unused else 0)
    for k in new:
        strings[k] = {}
    for k in unused:
        strings[k]["extractionState"] = "stale"
    catalog["strings"] = dict(sorted(strings.items()))
    with open(CATALOG, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, separators=(",", " : "))
        f.write("\n")
    print("added %d key(s), marked %d stale. Translate the new keys to vi, then run the tests." % (len(new), len(unused)))


if __name__ == "__main__":
    main()
