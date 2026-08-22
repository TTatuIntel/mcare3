"""Render and inspect the generated blueprint PDF without external Poppler."""

from __future__ import annotations

import math
from pathlib import Path

import pdfplumber
import pypdfium2 as pdfium
from PIL import Image, ImageDraw
from pypdf import PdfReader


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
PDF_PATH = REPO / "output" / "pdf" / "mcare-guided-operations-design-blueprint.pdf"
RENDER_DIR = REPO / "tmp" / "pdfs" / "mcare-blueprint-pages"
CONTACT_DIR = REPO / "tmp" / "pdfs" / "mcare-blueprint-contact"


def main() -> None:
    RENDER_DIR.mkdir(parents=True, exist_ok=True)
    CONTACT_DIR.mkdir(parents=True, exist_ok=True)
    for old in RENDER_DIR.glob("page-*.png"):
        old.unlink()
    for old in CONTACT_DIR.glob("contact-*.png"):
        old.unlink()

    reader = PdfReader(str(PDF_PATH))
    print(f"pages={len(reader.pages)}")
    print(f"metadata_title={reader.metadata.title}")

    pdf = pdfium.PdfDocument(str(PDF_PATH))
    rendered_paths: list[Path] = []
    for index in range(len(pdf)):
        page = pdf[index]
        bitmap = page.render(scale=1.35)
        image = bitmap.to_pil().convert("RGB")
        out = RENDER_DIR / f"page-{index + 1:03d}.png"
        image.save(out, "PNG", optimize=True)
        rendered_paths.append(out)
        page.close()

    with pdfplumber.open(str(PDF_PATH)) as inspection:
        blank = []
        overflow_candidates = []
        for index, page in enumerate(inspection.pages, start=1):
            text = (page.extract_text() or "").strip()
            if len(text) < 20:
                blank.append(index)
            words = page.extract_words() or []
            for word in words:
                if word.get("x0", 0) < -0.5 or word.get("x1", 0) > page.width + 0.5:
                    overflow_candidates.append((index, word.get("text")))
                    break
        print(f"blank_or_image_only_pages={blank}")
        print(f"horizontal_overflow_candidates={overflow_candidates}")

    thumb_w = 260
    thumb_h = 368
    columns = 3
    rows = 3
    per_sheet = columns * rows
    for sheet_index in range(math.ceil(len(rendered_paths) / per_sheet)):
        subset = rendered_paths[sheet_index * per_sheet : (sheet_index + 1) * per_sheet]
        sheet = Image.new("RGB", (columns * thumb_w, rows * thumb_h), "#DDE3EC")
        draw = ImageDraw.Draw(sheet)
        for slot, path in enumerate(subset):
            with Image.open(path) as page_image:
                thumb = page_image.copy()
                thumb.thumbnail((thumb_w - 12, thumb_h - 24), Image.Resampling.LANCZOS)
            x = (slot % columns) * thumb_w + (thumb_w - thumb.width) // 2
            y = (slot // columns) * thumb_h + 18
            sheet.paste(thumb, (x, y))
            draw.text((slot % columns * thumb_w + 7, slot // columns * thumb_h + 3), f"Page {sheet_index * per_sheet + slot + 1}", fill="#172033")
        sheet.save(CONTACT_DIR / f"contact-{sheet_index + 1:02d}.png", "PNG", optimize=True)

    print(f"render_dir={RENDER_DIR}")
    print(f"contact_dir={CONTACT_DIR}")


if __name__ == "__main__":
    main()
