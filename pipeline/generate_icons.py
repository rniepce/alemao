"""Gera 4 opções de ícone para o app Alemão via Gemini Imagen.

Output: pipeline/output/icons/icon_v{1..4}.png (1024×1024 cada).
Depois, escolha uma e copie para ios/Alemao/Alemao/Assets.xcassets/AppIcon.appiconset/.
"""
from __future__ import annotations

from pathlib import Path

from google import genai
from google.genai import types

from alemao_pipeline import config

OUTPUT_DIR = Path(__file__).parent / "output" / "icons"


PROMPTS = [
    # v1 — minimalista colorido (cores da bandeira)
    {
        "name": "v1_minimal_flag",
        "prompt": (
            "iOS app icon, 1024×1024 square, gradient background from deep black through "
            "vermilion red to warm gold (German flag colors, but softened and modern). "
            "Centered minimalist white letter 'Ä' with umlaut clearly visible, sans-serif, "
            "subtle drop shadow. Clean and professional, suitable for App Store. "
            "No text other than the letter. No frame, no border, no logos. Square."
        ),
    },
    # v2 — livro + balão de fala (educativo)
    {
        "name": "v2_book_speech",
        "prompt": (
            "iOS app icon, 1024×1024 square. Blue-to-purple gradient background. "
            "Centered illustration: an open white book transitioning into a soft speech "
            "bubble at the top, suggesting language learning. Pages of the book hint at "
            "German letters. Modern flat design, minimalist, professional. "
            "No text outside the illustration. Smooth rounded corners on inside elements."
        ),
    },
    # v3 — bandeira moderna estilizada
    {
        "name": "v3_modern_flag",
        "prompt": (
            "iOS app icon, 1024×1024 square. Modern abstract interpretation of the German "
            "flag: three diagonal bands (black, red, gold) flowing from upper-left to lower-right, "
            "stylized with soft edges and slight gradient. Centered on top: a small white "
            "open book or letter 'A' symbol. Clean, professional, suitable for an educational "
            "language app. No text."
        ),
    },
    # v4 — abstrato simbólico
    {
        "name": "v4_abstract_symbol",
        "prompt": (
            "iOS app icon, 1024×1024 square. Solid deep teal background. Centered: "
            "a stylized abstract symbol combining two German umlaut dots arranged above "
            "a curved line that suggests both an open book and a smile. Warm gold/yellow "
            "accents. Modern flat design, minimalist, sophisticated. Suitable for a "
            "premium educational app. No text."
        ),
    },
]


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    client = genai.Client(api_key=config.gemini_api_key())

    for spec in PROMPTS:
        print(f"→ Gerando {spec['name']}…")
        try:
            response = client.models.generate_images(
                model="imagen-4.0-generate-001",
                prompt=spec["prompt"],
                config=types.GenerateImagesConfig(
                    number_of_images=1,
                    aspect_ratio="1:1",
                    person_generation="dont_allow",
                ),
            )
            if not response.generated_images:
                print(f"  [!] sem imagem retornada (filtro de segurança?)")
                continue
            img = response.generated_images[0]
            out = OUTPUT_DIR / f"{spec['name']}.png"
            out.write_bytes(img.image.image_bytes)
            print(f"  ✓ {out} ({len(img.image.image_bytes):,} bytes)")
        except Exception as e:
            print(f"  [x] falhou: {e}")


if __name__ == "__main__":
    main()
