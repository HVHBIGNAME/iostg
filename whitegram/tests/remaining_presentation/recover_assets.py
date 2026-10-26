"""Copy two exact shipped loose badges into the owned resource fixture directories."""
import argparse
import hashlib
from pathlib import Path
import struct
import zipfile

HASHES = {
    "WGBadgeBlack": "16e707432b2b8a52a2c10c7766ac26fa0d77faa2c693a37e83e61b9b15717219",
    "WGBadgeWhite": "cda3a6b7c104fd6ab87784551a06f52a77bf232c14ef1079f27490f62724ad6f",
}


def recover(ipa):
    with ipa.open("rb") as stream:
        assert hashlib.file_digest(stream, "sha256").hexdigest() == "5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf"
    with zipfile.ZipFile(ipa) as archive:
        for name, digest in HASHES.items():
            data = archive.read("Payload/Telegram.app/" + name + ".png")
            assert hashlib.sha256(data).hexdigest() == digest
            target = Path(__file__).parent / "assets" / (name + ".imageset") / (name + ".png")
            if target.exists():
                assert target.read_bytes() == data
            else:
                with target.open("xb") as output:
                    output.write(data)
            width, height = struct.unpack_from(">II", data, data.index(b"IHDR") + 4)
            print(name, len(data), digest, "pixels", width, height)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    recover(parser.parse_args().ipa)
