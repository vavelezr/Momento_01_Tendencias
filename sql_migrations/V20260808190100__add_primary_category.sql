-- Columna nueva: categoría principal denormalizada del negocio, para no tener que hacer
-- JOIN contra business_category + category en las consultas más frecuentes del dashboard
-- ("¿qué categoría de negocio tiene mejor calificación promedio?").
--
-- Se puebla en un paso aparte (SQL Editor de Neon) a partir de business_category — no en
-- esta migración, que solo agrega la columna.

ALTER TABLE business ADD COLUMN primary_category VARCHAR(100);
