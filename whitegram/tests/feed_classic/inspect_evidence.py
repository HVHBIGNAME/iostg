"""Project the locally recovered evidence without re-opening the IPA."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("path", type=Path)
parser.add_argument("--function")
parser.add_argument("--assembly", action="store_true")
args = parser.parse_args()
data = json.loads(args.path.read_text(encoding="utf-8"))
for label, image in data["images"].items():
    if args.function:
        for function in image["functions"]:
            if function["start"] == args.function:
                print(label, function["start"], function["end"], function["sha256"])
                print("\n".join(function["assembly"] if args.assembly else [line for line in function["assembly"] if "; " in line]))
    else:
        print(label)
        print(json.dumps({"types": [{"name": item["name"], "accessor": item.get("metadata_accessor"), "fields": [field["name"] for field in item["fields"]]} for item in image["types"]],
            "classes": image["objc_classes"], "posts_calls": [call for call in image["preference_calls"] if "showPostsFeed" in call["name"]]}, indent=2))
