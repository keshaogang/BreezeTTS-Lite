#!/usr/bin/env python3
"""gen_project.py 之后再打三个补丁：bundle id、产品名、纯 arm64。

    python3 scripts/patch_lite.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "BreezeTTS.xcodeproj", "project.pbxproj")

src = open(PATH, encoding="utf-8").read()
src = src.replace("PRODUCT_BUNDLE_IDENTIFIER = com.breeze.BreezeTTS;",
                  "PRODUCT_BUNDLE_IDENTIFIER = com.breezespeak.lite;")
src = src.replace('PRODUCT_NAME = "$(TARGET_NAME)";', 'PRODUCT_NAME = "BreezeTTS Lite";')
src = src.replace("ARCHS = (\n\t\t\t\t\tarm64,\n\t\t\t\t\tx86_64,\n\t\t\t\t);", "ARCHS = arm64;")
open(PATH, "w", encoding="utf-8").write(src)

print("patched:", {
    "bundle": "com.breezespeak.lite" in src,
    "name": 'PRODUCT_NAME = "BreezeTTS Lite";' in src,
    "arm64": "ARCHS = arm64;" in src,
})
