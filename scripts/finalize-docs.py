#!/usr/bin/env python3
"""Add deployment-specific metadata that Moat v0.6.2 does not generate."""

from __future__ import annotations

import html
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def page_url(site_dir: Path, page: Path, site_url: str) -> str:
    relative = page.relative_to(site_dir)
    if relative == Path("index.html"):
        return f"{site_url}/"
    if relative.name == "index.html":
        return f"{site_url}/{relative.parent.as_posix()}/"
    return f"{site_url}/{relative.as_posix()}"


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: finalize-docs.py SITE_DIR SITE_URL", file=sys.stderr)
        return 2

    site_dir = Path(sys.argv[1]).resolve()
    site_url = sys.argv[2].rstrip("/")
    pages = sorted(site_dir.rglob("*.html"))
    if not pages:
        print(f"no HTML pages found under {site_dir}", file=sys.stderr)
        return 1

    urls: list[str] = []
    for page in pages:
        canonical = page_url(site_dir, page, site_url)
        content = page.read_text(encoding="utf-8")
        if 'rel="canonical"' in content:
            print(f"canonical link already exists in {page}", file=sys.stderr)
            return 1
        marker = "</head>"
        if marker not in content:
            print(f"missing </head> in {page}", file=sys.stderr)
            return 1
        tag = f'  <link rel="canonical" href="{html.escape(canonical, quote=True)}">\n'
        page.write_text(content.replace(marker, tag + marker, 1), encoding="utf-8")
        urls.append(canonical)

    namespace = "http://www.sitemaps.org/schemas/sitemap/0.9"
    ET.register_namespace("", namespace)
    urlset = ET.Element(f"{{{namespace}}}urlset")
    for url in urls:
        entry = ET.SubElement(urlset, f"{{{namespace}}}url")
        ET.SubElement(entry, f"{{{namespace}}}loc").text = url
    ET.indent(urlset, space="  ")
    ET.ElementTree(urlset).write(
        site_dir / "sitemap.xml", encoding="utf-8", xml_declaration=True
    )

    (site_dir / "robots.txt").write_text(
        f"User-agent: *\nAllow: /\nSitemap: {site_url}/sitemap.xml\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
