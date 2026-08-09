-- Roll forward: primary_category se quedaba corta con categorías reales del dataset.
-- Ejemplo real que dispara el error ("Health & Medical", 16 caracteres) documentado en
-- docs/evidences/README.md — value too long for type character varying(15).
--
-- No se edita V20260808190100__add_primary_category.sql (ya aplicada en dev y main): eso
-- rompería el checksum que Flyway ya tiene registrado para esa versión. El roll forward
-- correcto es una migración nueva que altera la columna existente.
ALTER TABLE business ALTER COLUMN primary_category TYPE VARCHAR(100);
