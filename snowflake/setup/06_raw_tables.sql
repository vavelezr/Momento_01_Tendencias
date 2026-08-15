-- Punto 1 — Arquitectura Snowflake como código (Momento 2).
-- Ejecutar como YELP_LOADER_ROLE (o ACCOUNTADMIN) — ya con el warehouse y los grants de
-- 01-04 en su lugar. Correrlo con YELP_LOADER_ROLE de una vez sirve como prueba de que
-- el rol de servicio de verdad puede crear tablas en RAW, antes de que el Punto 2
-- dependa de eso.
--
-- Seis tablas, una por entidad real del modelo transaccional del Momento 1 (Neon +
-- Flyway) — ver docs/dominio_de_negocio.md del repo. Son espejo de las tablas de origen,
-- no una versión curada: la capa RAW es deliberadamente permisiva (sin PK/FK/NOT NULL
-- forzados, tipos amplios) porque su único trabajo es recibir la carga cruda del Punto 2
-- sin rechazar filas por un tipo mal calculado. El tipado estricto y las relaciones son
-- trabajo de una capa STAGING/marts posterior, no de RAW.
--
-- Snowflake no aplica (no "enforces") PRIMARY KEY/FOREIGN KEY — se documentan igual como
-- comentario de columna porque describen el modelo real y las herramientas de este
-- ecosistema (dbt docs, editores SQL) sí los usan para generar diagramas y autocompletar.

USE DATABASE YELP_GOODYEAR_DW;
USE SCHEMA RAW;

CREATE TABLE IF NOT EXISTS CATEGORY (
    ID   NUMBER        COMMENT 'PK. Catálogo de categorías de negocio (192 en la muestra de Goodyear, AZ).',
    NAME VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS BUSINESS (
    BUSINESS_ID       VARCHAR(50)   COMMENT 'PK.',
    NAME              VARCHAR(500),
    FULL_ADDRESS      VARCHAR(500),
    CITY              VARCHAR(100),
    STATE             VARCHAR(10),
    LATITUDE          NUMBER(9, 7),
    LONGITUDE         NUMBER(10, 7),
    STARS             NUMBER(2, 1),
    REVIEW_COUNT      NUMBER,
    IS_OPEN           BOOLEAN,
    PRIMARY_CATEGORY  VARCHAR(100)  COMMENT 'Denormalizada desde BUSINESS_CATEGORY + CATEGORY. Llegó vía migración Flyway V__ en el Momento 1.'
);

CREATE TABLE IF NOT EXISTS BUSINESS_CATEGORY (
    BUSINESS_ID  VARCHAR(50)  COMMENT 'PK compuesta (BUSINESS_ID, CATEGORY_ID). FK -> BUSINESS.BUSINESS_ID.',
    CATEGORY_ID  NUMBER       COMMENT 'FK -> CATEGORY.ID.'
);

CREATE TABLE IF NOT EXISTS USERS (
    USER_ID        VARCHAR(50)   COMMENT 'PK.',
    NAME           VARCHAR(200),
    REVIEW_COUNT   NUMBER,
    YELPING_SINCE  DATE          COMMENT 'Solo trae año-mes en la fuente; se normaliza al día 1 del mes desde Neon.',
    AVERAGE_STARS  NUMBER(3, 2),
    FANS           NUMBER,
    VOTES_USEFUL   NUMBER,
    VOTES_FUNNY    NUMBER,
    VOTES_COOL     NUMBER
);

CREATE TABLE IF NOT EXISTS REVIEW (
    REVIEW_ID     VARCHAR(50)  COMMENT 'PK.',
    BUSINESS_ID   VARCHAR(50)  COMMENT 'FK -> BUSINESS.BUSINESS_ID.',
    USER_ID       VARCHAR(50)  COMMENT 'FK -> USERS.USER_ID.',
    STARS         NUMBER(1, 0) COMMENT 'Entre 1 y 5 en el origen (CHECK en Neon; no forzado aquí).',
    REVIEW_DATE   DATE,
    TEXT          VARCHAR(16777216),
    VOTES_USEFUL  NUMBER,
    VOTES_FUNNY   NUMBER,
    VOTES_COOL    NUMBER
);

CREATE TABLE IF NOT EXISTS TIP (
    TIP_ID       NUMBER        COMMENT 'PK.',
    BUSINESS_ID  VARCHAR(50)   COMMENT 'FK -> BUSINESS.BUSINESS_ID.',
    USER_ID      VARCHAR(50)   COMMENT 'FK -> USERS.USER_ID.',
    TIP_TEXT     VARCHAR(2000),
    TIP_DATE     DATE,
    LIKES        NUMBER        DEFAULT 0
);
