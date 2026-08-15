-- Columna nueva: etiqueta de sentimiento sobre el texto de la reseña. Nace vacía
-- (NULL) para el histórico — es un campo de enriquecimiento, no algo que la reseña
-- "debería" haber tenido siempre, así que NULL comunica "no calculado todavía", no
-- "se sabe que no tiene sentimiento".
--
-- Usada también como ejercicio de schema drift para la ingesta a Snowflake (Momento 2,
-- Sesión 4): se aplicó primero directo en Neon dev para provocar el drift a propósito,
-- y esta migración la formaliza como parte permanente del modelo — ver
-- docs/evidences/README.md, sección Momento 2.
ALTER TABLE review ADD COLUMN sentiment_label VARCHAR(20);
