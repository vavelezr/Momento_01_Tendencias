-- Índice + restricciones (requisito mínimo del Momento 1).
--
-- Índice compuesto: la consulta más común sobre `review` es "las reseñas más recientes de
-- este negocio" — business_id como filtro, review_date DESC como orden. Un índice simple
-- por business_id ya existe desde el baseline (inyeccion_semilla.py); este lo reemplaza por
-- uno compuesto que también cubre el ORDER BY.
DROP INDEX IF EXISTS idx_review_business_id;
CREATE INDEX idx_review_business_id_review_date
    ON review (business_id, review_date DESC);

-- Restricciones: `review.stars BETWEEN 1 AND 5` ya quedó como CHECK desde el baseline.
-- `checkin.day_index`/`hour_of_day` llegaron sin restricción de rango en su migración
-- (V__add_checkin.sql) a propósito, para no mezclar "tabla nueva" con "restricción nueva"
-- en el mismo cambio — se agregan aquí.
ALTER TABLE checkin
    ADD CONSTRAINT chk_checkin_day_index CHECK (day_index BETWEEN 0 AND 6);

ALTER TABLE checkin
    ADD CONSTRAINT chk_checkin_hour_of_day CHECK (hour_of_day BETWEEN 0 AND 23);
