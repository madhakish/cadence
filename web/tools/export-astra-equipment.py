"""Copy the production equipment photographs byte-for-byte from the native app."""
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "Cadence/Assets.xcassets"
OUTPUT = ROOT / "web/app/assets"


def export(name, destination):
    folder = CATALOG / (name + ".imageset")
    images = json.loads((folder / "Contents.json").read_text())["images"]
    source = folder / next(image["filename"] for image in images if "filename" in image)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def main():
    export("AstraMainEquipmentContext", OUTPUT / "astra/main-context.jpg")
    export("AstraDumbbell", OUTPUT / "astra/dumbbell.png")
    for wood in ("", "Walnut", "WhiteOak", "Maple"):
        name = "AstraPhotoStage" + wood
        export(name, OUTPUT / "photo" / (name + ".jpg"))
    parts = ["PhotoFace" + finish for finish in
             ("Rubber", "BlackRubber", "Gloss", "Coated", "Iron", "Hammertone", "Machined")]
    parts += ["PhotoEdge" + finish for finish in ("Rubber", "Coated", "Iron")]
    parts += ["Photo" + part for part in ("Brand", "Mark45lb", "Mark20kg", "Mark15kg", "Hub", "Shaft", "Sleeve", "Shoulder", "Collar", "Endcap")]
    for part in parts:
        export(part, OUTPUT / "photo" / (part + ".png"))


if __name__ == "__main__":
    main()
