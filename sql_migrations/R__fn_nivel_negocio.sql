-- Función repetible: clasifica un negocio en un nivel de reputación combinando su
-- calificación promedio (business.stars) y su volumen de reseñas (business.review_count).
--
-- Es lógica de negocio pura (no toca tablas, no inserta datos) y los umbrales son de los
-- que cambian con el tiempo (marketing decide subir/bajar el corte de "Destacado"), así que
-- va en R__ y no en V__: si el archivo cambia, Flyway lo vuelve a aplicar solo, sin generar
-- una migración versionada nueva por cada ajuste de negocio.

CREATE OR REPLACE FUNCTION fn_nivel_negocio(p_stars NUMERIC, p_review_count INTEGER)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_stars IS NULL OR p_review_count IS NULL THEN
        RETURN NULL;
    END IF;

    -- Menos de 5 reseñas: no hay evidencia suficiente para calificar, sin importar cuán
    -- alto sea el promedio. Un negocio con 1 reseña de 5 estrellas no es "Destacado".
    IF p_review_count < 5 THEN
        RETURN 'Nuevo';
    ELSIF p_stars >= 4.5 AND p_review_count >= 50 THEN
        RETURN 'Destacado';
    ELSIF p_stars >= 4.0 AND p_review_count >= 10 THEN
        RETURN 'Recomendado';
    ELSE
        RETURN 'Regular';
    END IF;
END;
$$;

-- ¿Por qué IMMUTABLE? Para los mismos dos argumentos, siempre devuelve lo mismo — no
-- consulta tablas ni depende de la hora. Le permite al planificador cachear el resultado,
-- igual que fn_calculate_discount en el curso.

COMMENT ON FUNCTION fn_nivel_negocio(NUMERIC, INTEGER) IS
    'Clasifica un negocio en Nuevo/Regular/Recomendado/Destacado según stars y review_count.';
