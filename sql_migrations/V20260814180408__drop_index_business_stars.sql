-- Roll forward: elimina el índice idx_business_stars creado en
-- V20260814175913__add_index_business_stars.sql (migración de práctica de la demo).
-- No se edita ni se borra esa migración vieja — eso rompería su checksum ya aplicado en
-- dev y en main. Se revierte hacia adelante, con una migración nueva.
DROP INDEX IF EXISTS idx_business_stars;
