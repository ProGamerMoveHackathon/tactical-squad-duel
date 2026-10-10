#!/usr/bin/env python3
"""Fetch ONLY the Web export templates for Godot from the official (1.3 GB) .tpz
archive using HTTP range requests, and install them where the editor expects them.

Usage: python3 tools/fetch_web_templates.py [version]   (default 4.7.2)
"""
import io
import os
import sys
import time
import urllib.error
import urllib.request
import zipfile

VERSION = sys.argv[1] if len(sys.argv) > 1 else "4.7.2"
URL = (f"https://github.com/godotengine/godot/releases/download/{VERSION}-stable/"
       f"Godot_v{VERSION}-stable_export_templates.tpz")

if sys.platform == "darwin":
    BASE = os.path.expanduser("~/Library/Application Support/Godot/export_templates")
elif os.name == "nt":
    BASE = os.path.join(os.environ["APPDATA"], "Godot", "export_templates")
else:
    BASE = os.path.expanduser("~/.local/share/godot/export_templates")
DEST = os.path.join(BASE, f"{VERSION}.stable")


class HttpRangeFile(io.RawIOBase):
    def __init__(self, url):
        self.headers = {"User-Agent": "Mozilla/5.0 (GodotTemplateFetcher/1.0)"}
        req = urllib.request.Request(url, method="HEAD", headers=self.headers)
        for attempt in range(5):
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    self.url = r.geturl()  # follow redirect once
                    self.size = int(r.headers["Content-Length"])
                break
            except Exception as e:
                if attempt == 4:
                    raise
                time.sleep(1 + attempt)
        self.pos = 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, offset, whence=0):
        if whence == 0:
            self.pos = offset
        elif whence == 1:
            self.pos += offset
        else:
            self.pos = self.size + offset
        return self.pos

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        if n == 0 or self.pos >= self.size:
            return b""
        end = min(self.pos + n, self.size) - 1
        headers = {**self.headers, "Range": f"bytes={self.pos}-{end}"}
        req = urllib.request.Request(self.url, headers=headers)
        for attempt in range(5):
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    data = r.read()
                self.pos += len(data)
                return data
            except Exception as e:
                if attempt == 4:
                    raise
                time.sleep(1 + attempt)

    def readinto(self, b):
        data = self.read(len(b))
        b[: len(data)] = data
        return len(data)


def main():
    os.makedirs(DEST, exist_ok=True)
    expected = ["web_release.zip", "web_debug.zip", "version.txt"]
    if all(os.path.exists(os.path.join(DEST, f)) and os.path.getsize(os.path.join(DEST, f)) > 0 for f in expected):
        print(f"Templates already present in {DEST}, skipping download.")
        return

    print(f"Opening {URL}")
    f = io.BufferedReader(HttpRangeFile(URL), buffer_size=1 << 20)
    with zipfile.ZipFile(f) as z:
        wanted = [n for n in z.namelist() if os.path.basename(n).startswith("web_") or n.endswith("version.txt")]
        for name in wanted:
            out = os.path.join(DEST, os.path.basename(name))
            print(f"  extracting {name} -> {out}")
            with z.open(name) as src, open(out, "wb") as dst:
                dst.write(src.read())
    print("Done. Installed web templates into", DEST)


if __name__ == "__main__":
    main()
