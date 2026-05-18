"""Cliente Gemini compartilhado para o pipeline.

Encapsula:
- Criação do cliente (singleton lazy)
- `generate_structured()` para chamadas de texto que esperam JSON validado por Pydantic
- `embed_batch()` para embeddings em lotes com retry exponencial
"""

from __future__ import annotations

import logging
from typing import Any, TypeVar

from google import genai
from google.genai import types
from pydantic import BaseModel
from tenacity import (
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)

from . import config

logger = logging.getLogger(__name__)

T = TypeVar("T", bound=BaseModel)


_client: genai.Client | None = None


def client() -> genai.Client:
    global _client
    if _client is None:
        _client = genai.Client(api_key=config.gemini_api_key())
    return _client


# ---------- Text generation --------------------------------------------------

class GeminiAPIError(Exception):
    pass


@retry(
    reraise=True,
    stop=stop_after_attempt(4),
    wait=wait_exponential(multiplier=2, min=2, max=30),
    retry=retry_if_exception_type((GeminiAPIError, ConnectionError, TimeoutError)),
)
def generate_structured(
    prompt: str,
    schema: type[T],
    *,
    model: str | None = None,
    system_instruction: str | None = None,
    temperature: float = 0.3,
) -> T:
    """Chama Gemini esperando saída JSON validada por um Pydantic model."""
    cfg = types.GenerateContentConfig(
        response_mime_type="application/json",
        response_schema=schema,
        temperature=temperature,
    )
    if system_instruction:
        cfg.system_instruction = system_instruction

    try:
        resp = client().models.generate_content(
            model=model or config.TEXT_MODEL,
            contents=prompt,
            config=cfg,
        )
    except Exception as e:  # pragma: no cover - rede
        raise GeminiAPIError(str(e)) from e

    # O SDK retorna .parsed quando response_schema é informado
    parsed = getattr(resp, "parsed", None)
    if parsed is None:
        # Fallback: tentar parsear .text como JSON
        import json

        try:
            data = json.loads(resp.text)
            return schema.model_validate(data)
        except Exception as e:
            raise GeminiAPIError(f"Resposta sem parsed e text não-JSON: {e}") from e
    return parsed


def generate_text(
    prompt: str,
    *,
    model: str | None = None,
    system_instruction: str | None = None,
    temperature: float = 0.3,
) -> str:
    """Geração simples de texto livre."""
    cfg = types.GenerateContentConfig(temperature=temperature)
    if system_instruction:
        cfg.system_instruction = system_instruction
    resp = client().models.generate_content(
        model=model or config.TEXT_MODEL,
        contents=prompt,
        config=cfg,
    )
    return resp.text or ""


# ---------- Embeddings -------------------------------------------------------

@retry(
    reraise=True,
    stop=stop_after_attempt(5),
    wait=wait_exponential(multiplier=2, min=2, max=60),
    retry=retry_if_exception_type((GeminiAPIError, ConnectionError, TimeoutError)),
)
def embed_batch(
    texts: list[str],
    *,
    task_type: str = "RETRIEVAL_DOCUMENT",
    model: str | None = None,
    dimension: int | None = None,
) -> list[list[float]]:
    """Embeda um batch de textos. Retorna lista paralela aos inputs.

    Args:
        texts: lista de strings (até EMBED_BATCH_SIZE).
        task_type: "RETRIEVAL_DOCUMENT" para ingestão; "RETRIEVAL_QUERY" para queries.
        model: nome do modelo (default gemini-embedding-001).
        dimension: output_dimensionality (default 768).
    """
    if not texts:
        return []

    cfg = types.EmbedContentConfig(
        task_type=task_type,
        output_dimensionality=dimension or config.EMBEDDING_DIMENSION,
    )

    try:
        result = client().models.embed_content(
            model=model or config.EMBEDDING_MODEL,
            contents=texts,
            config=cfg,
        )
    except Exception as e:  # pragma: no cover
        raise GeminiAPIError(str(e)) from e

    return [e.values for e in result.embeddings]


# ---------- Utilidades -------------------------------------------------------

def safe_call(fn, *args, **kwargs) -> Any:
    """Wrapper genérico que loga erros sem propagar (útil em loops)."""
    try:
        return fn(*args, **kwargs)
    except Exception as e:
        logger.exception("Chamada Gemini falhou: %s", e)
        return None
