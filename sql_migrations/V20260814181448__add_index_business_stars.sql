-- Índice sobre business.stars: soporta las consultas de "negocios mejor calificados"
-- (ORDER BY stars DESC) y es justo el campo que usa fn_nivel_negocio (R__) para
-- clasificar un negocio como Destacado / Recomendado / Regular / Nuevo.
CREATE INDEX idx_business_stars ON business (stars DESC);
