#!/usr/bin/env python3
"""Check metadata and site-local links in a rendered Moat site."""

from __future__ import annotations

import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlparse


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.canonical: str | None = None
        self.description: str | None = None
        self.ids: set[str] = set()
        self.in_title = False
        self.links: list[str] = []
        self.title_parts: list[str] = []

    @property
    def title(self) -> str:
        return "".join(self.title_parts).strip()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if identifier := values.get("id"):
            self.ids.add(identifier)
        if tag == "title":
            self.in_title = True
        if tag == "meta" and values.get("name") == "description":
            self.description = values.get("content")
        if tag == "link" and values.get("rel") == "canonical":
            self.canonical = values.get("href")
        for attribute in ("href", "src"):
            if value := values.get(attribute):
                self.links.append(value)

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self.in_title = False

    def handle_data(self, data: str) -> None:
        if self.in_title:
            self.title_parts.append(data)


def public_path(site_dir: Path, page: Path, base_path: str) -> str:
    relative = page.relative_to(site_dir)
    if relative == Path("index.html"):
        return f"{base_path}/"
    if relative.name == "index.html":
        return f"{base_path}/{relative.parent.as_posix()}/"
    return f"{base_path}/{relative.as_posix()}"


def target_file(site_dir: Path, path: str, base_path: str) -> Path | None:
    if path == base_path or path == f"{base_path}/":
        return site_dir / "index.html"
    prefix = f"{base_path}/"
    if not path.startswith(prefix):
        return None
    relative = unquote(path[len(prefix) :])
    target = site_dir / relative
    if path.endswith("/"):
        target /= "index.html"
    return target


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: check-built-docs.py SITE_DIR BASE_PATH SITE_URL",
            file=sys.stderr,
        )
        return 2

    site_dir = Path(sys.argv[1]).resolve()
    base_path = "/" + sys.argv[2].strip("/")
    site_url = sys.argv[3].rstrip("/")
    errors: list[str] = []
    parsed_pages: dict[Path, PageParser] = {}

    for page in sorted(site_dir.rglob("*.html")):
        parser = PageParser()
        parser.feed(page.read_text(encoding="utf-8"))
        parsed_pages[page] = parser
        label = page.relative_to(site_dir)
        expected_canonical = site_url + public_path(site_dir, page, base_path)[len(base_path) :]
        if not parser.title:
            errors.append(f"{label}: missing <title>")
        if parser.title.startswith("Index —"):
            errors.append(f"{label}: generic Index page title")
        if not parser.description:
            errors.append(f"{label}: missing meta description")
        if parser.canonical != expected_canonical:
            errors.append(
                f"{label}: canonical is {parser.canonical!r}, expected {expected_canonical!r}"
            )

    if not parsed_pages:
        errors.append("no rendered HTML pages found")

    for required in (site_dir / "sitemap.xml", site_dir / "robots.txt"):
        if not required.is_file():
            errors.append(f"missing generated {required.name}")

    for page, parser in parsed_pages.items():
        label = page.relative_to(site_dir)
        current = "https://docs.invalid" + public_path(site_dir, page, base_path)
        for link in parser.links:
            parsed = urlparse(urljoin(current, link))
            if parsed.scheme not in ("", "https") or parsed.netloc != "docs.invalid":
                continue
            target = target_file(site_dir, parsed.path, base_path)
            if target is None:
                errors.append(f"{label}: site-local link escapes base path: {link}")
                continue
            if not target.is_file():
                errors.append(f"{label}: broken link {link} -> {target.relative_to(site_dir)}")
                continue
            if parsed.fragment and target.suffix == ".html":
                target_parser = parsed_pages.get(target.resolve())
                if target_parser is None or unquote(parsed.fragment) not in target_parser.ids:
                    errors.append(f"{label}: missing fragment target {link}")

    if errors:
        print("documentation validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"validated {len(parsed_pages)} rendered pages")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
