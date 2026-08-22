"""Render and inspect the complete application blueprint without Poppler.

Run after the PDF build with Python 3.11:
    py -3.11 docs/design/application/render_complete_application_pdf.py
"""

from __future__ import annotations

import math
from pathlib import Path

import pdfplumber
import pypdfium2 as pdfium
from PIL import Image, ImageDraw
from pypdf import PdfReader


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
PDF_PATH = REPO / "output" / "pdf" / "mcare-complete-application-design-blueprint.pdf"
RENDER_DIR = REPO / "tmp" / "pdfs" / "mcare-complete-blueprint-pages"
CONTACT_DIR = REPO / "tmp" / "pdfs" / "mcare-complete-blueprint-contact"


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
    rendered: list[Path] = []
    for index in range(len(pdf)):
        page = pdf[index]
        bitmap = page.render(scale=1.35)
        image = bitmap.to_pil().convert("RGB")
        out = RENDER_DIR / f"page-{index + 1:03d}.png"
        image.save(out, "PNG", optimize=True)
        rendered.append(out)
        page.close()

    with pdfplumber.open(str(PDF_PATH)) as inspection:
        blank = []
        overflow = []
        replacement_glyph_pages = []
        total_chars = 0
        for index, page in enumerate(inspection.pages, start=1):
            text = page.extract_text() or ""
            total_chars += len(text)
            if len(text.strip()) < 20:
                blank.append(index)
            if "\ufffd" in text:
                replacement_glyph_pages.append(index)
            for word in page.extract_words() or []:
                if word.get("x0", 0) < -0.5 or word.get("x1", 0) > page.width + 0.5:
                    overflow.append((index, word.get("text")))
                    break
        print(f"extracted_text_chars={total_chars}")
        print(f"blank_or_image_only_pages={blank}")
        print(f"horizontal_overflow_candidates={overflow}")
        print(f"replacement_glyph_pages={replacement_glyph_pages}")

    thumb_w, thumb_h = 260, 368
    columns, rows = 3, 3
    per_sheet = columns * rows
    for sheet_index in range(math.ceil(len(rendered) / per_sheet)):
        subset = rendered[sheet_index * per_sheet : (sheet_index + 1) * per_sheet]
        sheet = Image.new("RGB", (columns * thumb_w, rows * thumb_h), "#DDE3EC")
        draw = ImageDraw.Draw(sheet)
        for slot, path in enumerate(subset):
            with Image.open(path) as page_image:
                thumb = page_image.copy()
                thumb.thumbnail((thumb_w - 12, thumb_h - 24), Image.Resampling.LANCZOS)
            x = (slot % columns) * thumb_w + (thumb_w - thumb.width) // 2
            y = (slot // columns) * thumb_h + 18
            sheet.paste(thumb, (x, y))
            page_number = sheet_index * per_sheet + slot + 1
            draw.text((slot % columns * thumb_w + 7, slot // columns * thumb_h + 3), f"Page {page_number}", fill="#172033")
        sheet.save(CONTACT_DIR / f"contact-{sheet_index + 1:02d}.png", "PNG", optimize=True)

    print(f"render_dir={RENDER_DIR}")
    print(f"contact_dir={CONTACT_DIR}")


if __name__ == "__main__":
    main()

