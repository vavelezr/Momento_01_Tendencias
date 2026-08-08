-- Índice + restricciones (requisito mínimo del Momento 1).
--
-- Índice compuesto: la consulta más común sobre `review` es "las reseñas más recientes de
-- este negocio" — business_id como filtro, review_date DESC como orden. Un índice simple
-- por business_id ya existe desde el baseline (inyeccion_semilla.py); este lo reemplaza por
-- uno compuesto que también cubre el ORDER BY.
DROP INDEX IF EXISTS idx_review_business_id;
CREATE INDEX idx_review_business_id_review_date
    ON review (business_id, review_date DESC);

-- Restricción: `review.stars BETWEEN 1 AND 5` ya quedó como CHECK desde el baseline, así
-- que no la repetimos aquí. `tip.likes` (la única tabla nueva del Momento 1, ver
-- V__add_tip.sql) llegó sin restricción de rango — un conteo de likes negativo no tiene
-- sentido de negocio, así que se agrega aquí.
ALTER TABLE tip
    ADD CONSTRAINT chk_tip_likes CHECK (likes >= 0);
