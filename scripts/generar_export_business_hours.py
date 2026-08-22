"""
Generador del export semi-estructurado — horario semanal por negocio (Momento 2).

Sesión 5 del módulo "Tendencias emergentes en desarrollo de software" (SI6010-5979).

`data/business_hours.json` es un registro plano por negocio+día (formato de tabla, no de
export). La rúbrica del Momento 2 pide una fuente semi-estructurada con un array anidado
real — el mismo patrón que `marketing_leads_*.json` usó en clase (`campaign` con
`high_profile_contacts`). Este script agrupa el horario real por `business_id` en un array
`weekly_hours`, y lo envuelve con el metadata de trazabilidad que un sistema real de
exportación agregaría solo (batch id, timestamp de generación) — eso sí se mockea con
Faker, porque no existe en el dato origen. El horario en sí (`weekly_hours`) es 100% real,
tomado de `data/business_hours.json`.

Salida: 2 archivos JSON en `data/business_hours_exports/`, simulando dos corridas
semanales del export (la mitad de los negocios en cada una), listos para
`PUT` + `COPY INTO ... STRIP_OUTER_ARRAY = TRUE` en el Internal Stage de Snowflake.

Uso:
    uv run scripts/generar_export_business_hours.py
"""

from __future__ import annotations

import json
import sys
import uuid
from collections import defaultdict
from pathlib import Path

from faker import Faker

# Mismo patrón que scripts/inyeccion_semilla.py: anclar en la raíz del repo (marcada por
# .git/ + data/) para que el script funcione sin importar desde qué carpeta se invoque.
def encontrar_raiz_repositorio(inicio: Path) -> Path:
    for candidato in [inicio, *inicio.parents]:
        if (candidato / ".git").exists() and (candidato / "data").is_dir():
            return candidato
    raise RuntimeError(
        "No se encontró la raíz del repositorio (se esperaba un directorio con .git/ y "
        f"data/). Búsqueda iniciada en: {inicio}"
    )


RAIZ = encontrar_raiz_repositorio(Path(__file__).resolve().parent)
ARCHIVO_ORIGEN = RAIZ / "data" / "business_hours.json"
DIRECTORIO_SALIDA = RAIZ / "data" / "business_hours_exports"

# El JSON origen no viene ordenado por día; sin este mapa, LATERAL FLATTEN produciría
# arrays con los días en orden de aparición aleatorio en vez de Monday -> Sunday.
ORDEN_DIAS = {
    "Monday": 0, "Tuesday": 1, "Wednesday": 2, "Thursday": 3,
    "Friday": 4, "Saturday": 5, "Sunday": 6,
}

SOURCE_SYSTEM = "goodyear-biz-portal"

fake = Faker()
Faker.seed(2026)  # export reproducible: mismo mock en cada corrida del script


def agrupar_por_negocio(registros: list[dict]) -> dict[str, list[dict]]:
    por_negocio: dict[str, list[dict]] = defaultdict(list)
    for r in registros:
        por_negocio[r["business_id"]].append(
            {
                "day_of_week": r["day_of_week"],
                "open_time": r["open_time"],
                "close_time": r["close_time"],
            }
        )
    for horario in por_negocio.values():
        horario.sort(key=lambda d: ORDEN_DIAS[d["day_of_week"]])
    return por_negocio


def construir_export(negocios: dict[str, list[dict]], generado_hace_semanas: int) -> list[dict]:
    # Metadata de trazabilidad por lote: lo que un sistema real de exportación estampa
    # solo, y que el dato origen (una tabla plana) no tiene. Esto es lo que se mockea.
    batch_id = str(uuid.uuid4())
    generado_en = fake.date_time_between(
        start_date=f"-{generado_hace_semanas}w",
        end_date=f"-{generado_hace_semanas - 1}w" if generado_hace_semanas > 1 else "now",
    ).isoformat()

    return [
        {
            "business_id": business_id,
            "export_batch_id": batch_id,
            "generated_at": generado_en,
            "source_system": SOURCE_SYSTEM,
            "weekly_hours": weekly_hours,
        }
        for business_id, weekly_hours in negocios.items()
    ]


def main() -> int:
    if not ARCHIVO_ORIGEN.exists():
        print(f"ERROR: no se encontró {ARCHIVO_ORIGEN}", file=sys.stderr)
        return 1

    with ARCHIVO_ORIGEN.open(encoding="utf-8") as f:
        registros = json.load(f)

    por_negocio = agrupar_por_negocio(registros)
    ids_negocios = sorted(por_negocio)  # orden estable para que el split sea reproducible

    # Dos exports semanales: cada uno cubre la mitad de los negocios, como si no todos
    # reportaran su horario la misma semana.
    mitad = len(ids_negocios) // 2
    lotes = [ids_negocios[:mitad], ids_negocios[mitad:]]

    DIRECTORIO_SALIDA.mkdir(parents=True, exist_ok=True)

    for numero, ids_lote in enumerate(lotes, start=1):
        negocios_lote = {bid: por_negocio[bid] for bid in ids_lote}
        # El lote 1 se generó hace más semanas que el lote 2, simulando corridas sucesivas.
        export = construir_export(negocios_lote, generado_hace_semanas=len(lotes) - numero + 1)

        ruta_salida = DIRECTORIO_SALIDA / f"business_hours_export_{numero}.json"
        with ruta_salida.open("w", encoding="utf-8") as f:
            json.dump(export, f, indent=2, ensure_ascii=False)

        print(f"{ruta_salida.relative_to(RAIZ)}  ({len(export)} negocios)")

    print(f"\nTotal negocios exportados: {len(ids_negocios)} en {len(lotes)} archivos.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
