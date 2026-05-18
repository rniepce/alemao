"""Extração de texto de PDFs.

Estratégia em camadas:
1. PyMuPDF (`fitz`) extrai texto direto e a TOC (table of contents).
2. Páginas com pouco/nenhum texto extraído → rasterizamos e rodamos OCR via
   pytesseract (idioma `deu` por padrão; cai para `eng` se `deu` não instalado).
3. O retorno é uma `ExtractedDocument` com lista de páginas (texto + bbox?) e a TOC.

Performance: para um livro de ~500 páginas com texto nativo, leva <10s. Para PDFs
escaneados (OCR em todas as páginas), pode levar vários minutos.
"""

from __future__ import annotations

import hashlib
import io
import logging
from dataclasses import dataclass, field
from pathlib import Path

import fitz  # PyMuPDF
from PIL import Image

logger = logging.getLogger(__name__)


# Limite mínimo de caracteres alfanuméricos por página para considerar que houve
# extração de texto bem-sucedida via PyMuPDF. Abaixo disso, tentamos OCR.
MIN_CHARS_PER_PAGE = 50


@dataclass
class ExtractedPage:
    page_number: int  # 1-indexed
    text: str
    via_ocr: bool = False


@dataclass
class TOCEntry:
    level: int
    title: str
    page: int  # 1-indexed


@dataclass
class ExtractedDocument:
    source_path: Path
    file_hash: str
    pages: list[ExtractedPage] = field(default_factory=list)
    toc: list[TOCEntry] = field(default_factory=list)
    page_count: int = 0
    ocr_pages: int = 0

    @property
    def full_text(self) -> str:
        return "\n\n".join(p.text for p in self.pages if p.text.strip())

    def first_n_pages_text(self, n: int = 10) -> str:
        return "\n\n".join(p.text for p in self.pages[:n] if p.text.strip())


def compute_file_hash(path: Path) -> str:
    """SHA-256 do arquivo, em hex. Usado para idempotência."""
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()


def _page_needs_ocr(text: str) -> bool:
    """Heurística simples: poucas letras → provavelmente é uma imagem digitalizada."""
    alnum = sum(1 for c in text if c.isalnum())
    return alnum < MIN_CHARS_PER_PAGE


def _ocr_page(page: fitz.Page, lang: str = "deu") -> str:
    """Renderiza a página como imagem e roda Tesseract."""
    try:
        import pytesseract
    except ImportError:
        logger.warning("pytesseract não instalado; pulando OCR")
        return ""

    from .config import TESSERACT_CMD

    if TESSERACT_CMD:
        pytesseract.pytesseract.tesseract_cmd = TESSERACT_CMD

    # 300 DPI para boa qualidade de OCR
    pix = page.get_pixmap(dpi=300)
    img = Image.open(io.BytesIO(pix.tobytes("png")))

    try:
        return pytesseract.image_to_string(img, lang=lang)
    except pytesseract.TesseractError as e:
        # Cai para inglês se o pacote alemão não estiver instalado
        if "deu" in str(e):
            logger.warning("Pacote tesseract-data-deu ausente; usando 'eng'")
            return pytesseract.image_to_string(img, lang="eng")
        raise


def extract_document(
    pdf_path: Path | str,
    *,
    ocr: bool = True,
    ocr_lang: str = "deu",
    max_pages: int | None = None,
) -> ExtractedDocument:
    """Extrai texto e TOC de um PDF.

    Args:
        pdf_path: caminho do PDF.
        ocr: se True, faz fallback para OCR em páginas vazias.
        ocr_lang: idioma do Tesseract (`deu`, `eng`, `por`, `deu+por`, etc.).
        max_pages: para testes — extrai apenas as N primeiras páginas.
    """
    pdf_path = Path(pdf_path)
    if not pdf_path.exists():
        raise FileNotFoundError(pdf_path)

    file_hash = compute_file_hash(pdf_path)
    doc = fitz.open(pdf_path)
    pages: list[ExtractedPage] = []
    ocr_count = 0
    total_pages = doc.page_count
    upper = total_pages if max_pages is None else min(max_pages, total_pages)

    for i in range(upper):
        page = doc.load_page(i)
        text = page.get_text("text") or ""
        via_ocr = False

        if ocr and _page_needs_ocr(text):
            try:
                ocr_text = _ocr_page(page, lang=ocr_lang)
                if len(ocr_text.strip()) > len(text.strip()):
                    text = ocr_text
                    via_ocr = True
                    ocr_count += 1
            except Exception as e:  # pragma: no cover
                logger.warning("OCR falhou na página %d de %s: %s", i + 1, pdf_path.name, e)

        pages.append(ExtractedPage(page_number=i + 1, text=text, via_ocr=via_ocr))

    toc_raw = doc.get_toc()  # [[level, title, page], ...]
    toc = [TOCEntry(level=lvl, title=title, page=pg) for lvl, title, pg in toc_raw]

    doc.close()

    return ExtractedDocument(
        source_path=pdf_path,
        file_hash=file_hash,
        pages=pages,
        toc=toc,
        page_count=total_pages,
        ocr_pages=ocr_count,
    )
