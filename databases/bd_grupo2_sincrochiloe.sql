-- ============================================================================
-- Script DDL Sincro Chiloé - [Grupo 2] 
-- Grupo: 2
-- Integrantes: Vicente Garín, Francisco Kroff, Benjamín Concha, José Guanel
-- SGBD: PostgreSQL 16
-- Base: bd_grupo2_sincrochiloe
-- Fecha original: 29/06/2026
--
-- CAMBIOS respecto al script original, según pauta de evaluación (76/100):
--   1. VARCHAR sin longitud -> se asignó longitud a todas las columnas VARCHAR.
--   2. Se agregó la entidad PUBLICACION_TRANSPORTE (lado del transportista
--      publicando disponibilidad; faltaba en el script original).
--   3. Se agregó la relación N:M CAMION-TIPO_CARGA (compatibilidad de flota).
--   4. Se aplicó el endurecimiento completo de la sección 3 del informe:
--      CHECK de dominio, CHECK de coherencia, UNIQUE y EXCLUDE (no solapamiento).
--   Cada bloque nuevo está marcado con "NUEVO" para que podamos indentificar mejor los cambios.
-- ============================================================================

-- ============================================================================
-- DECISIONES TOMADAS
-- ============================================================================
-- 1. PUBLICACION_TRANSPORTE se agregó como espejo de PUBLICACION_CARGA para
--    que el transportista también pueda publicar capacidad disponible; sin
--    esta tabla el marketplace de "carga de retorno" solo funcionaba en una
--    dirección (cliente publica, transportista nunca).
-- 2. CAMION_TIPO_CARGA resuelve la cardinalidad N:M de compatibilidad de
--    flota (qué tipos de carga puede llevar cada camión); la validación
--    semántica más fina (ej. camión sin frío no debería marcar compatibilidad
--    con "Perecederos") se deja a nivel de aplicación, no de constraint.
-- 3. tarifa_final en VIAJE queda desnormalizada a propósito: congela el valor
--    cobrado en el momento del viaje para que cambios futuros en
--    TARIFA_REFERENCIAL no alteren registros históricos ni la facturación ya
--    cerrada.
-- 4. camion_id_actual / chofer_id_actual en VIAJE son columnas espejo,
--    sincronizadas por el trigger sync_actores_viaje() cada vez que cambia
--    match_id. Se necesitan porque PostgreSQL no permite construir un
--    EXCLUDE que referencie columnas de otra tabla (camion_id/chofer_id
--    viven en MATCH, pero el rango temporal vive en VIAJE).
-- 5. Los CHECK de dominio (estado, emisor, tipo_evento) reemplazan columnas
--    de texto libre por conjuntos cerrados de valores, evitando datos
--    inconsistentes que antes rompían filtros como el de la consulta 9.
-- 6. Las restricciones EXCLUDE (tarifa_referencial y viaje) requieren la
--    extensión btree_gist para poder combinar igualdad (ruta_id/tipo_carga_id,
--    camion_id/chofer_id) con solapamiento de rangos de fecha/tiempo.
-- 7. UNIQUE(publicacion_id, transportista_id) en POSTULACION impide que un
--    mismo transportista postule más de una vez a la misma publicación.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. LIMPIEZA DE ENTORNO (Orden inverso de dependencias para CASCADE)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS notificacion CASCADE;
DROP TABLE IF EXISTS historial_cumplimiento CASCADE;
DROP TABLE IF EXISTS calificacion CASCADE;
DROP TABLE IF EXISTS viaje CASCADE;
DROP TABLE IF EXISTS comunicacion CASCADE;
DROP TABLE IF EXISTS match CASCADE;
DROP TABLE IF EXISTS postulacion CASCADE;
DROP TABLE IF EXISTS publicacion_transporte CASCADE; -- NUEVO
DROP TABLE IF EXISTS publicacion_carga CASCADE;
DROP TABLE IF EXISTS tarifa_referencial CASCADE;
DROP TABLE IF EXISTS ruta CASCADE;
DROP TABLE IF EXISTS cruce_maritimo CASCADE;
DROP TABLE IF EXISTS carga CASCADE;
DROP TABLE IF EXISTS camion_tipo_carga CASCADE; -- NUEVO
DROP TABLE IF EXISTS tipo_carga CASCADE;
DROP TABLE IF EXISTS chofer CASCADE;
DROP TABLE IF EXISTS camion CASCADE;
DROP TABLE IF EXISTS transportista CASCADE;
DROP TABLE IF EXISTS cliente CASCADE;
DROP TABLE IF EXISTS tipo_cliente CASCADE;
DROP FUNCTION IF EXISTS sync_actores_viaje() CASCADE; -- NUEVO

-- ============================================================================
-- FASE 1: ENTIDADES MAESTRAS GENERALES
-- ============================================================================

CREATE TABLE tipo_cliente (
    id_tipo_cliente SERIAL PRIMARY KEY,
    nombre_tipo VARCHAR(50) NOT NULL UNIQUE,
    descripcion VARCHAR(255)
);

CREATE TABLE tipo_carga (
    id_tipo_carga SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE,
    requiere_refrigeracion BOOLEAN NOT NULL DEFAULT FALSE,
    es_peligrosa BOOLEAN NOT NULL DEFAULT FALSE,
    descripcion VARCHAR(255)
);

CREATE TABLE cruce_maritimo (
    id_cruce SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    empresa_naviera VARCHAR(100) NOT NULL,
    duracion_estimada_min INTEGER NOT NULL CHECK (duracion_estimada_min > 0),
    tarifa_cruce NUMERIC NOT NULL CHECK (tarifa_cruce >= 0)
);

-- ============================================================================
-- FASE 2: ACTORES Y CONFIGURACIÓN DE ACTORES
-- ============================================================================

CREATE TABLE cliente (
    id_cliente SERIAL PRIMARY KEY,
    tipo_cliente_id INTEGER NOT NULL,
    rut VARCHAR(12) NOT NULL UNIQUE,
    nombre_razon_social VARCHAR(150) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    telefono VARCHAR(20) NOT NULL,
    direccion VARCHAR(200),
    comuna VARCHAR(100),
    fecha_registro TIMESTAMP DEFAULT NOW(),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_cliente_tipo_cliente FOREIGN KEY (tipo_cliente_id) REFERENCES tipo_cliente(id_tipo_cliente) ON UPDATE CASCADE
);

CREATE TABLE transportista (
    id_transportista SERIAL PRIMARY KEY,
    rut_empresa VARCHAR(12) NOT NULL UNIQUE,
    razon_social VARCHAR(150) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    telefono VARCHAR(20) NOT NULL,
    direccion VARCHAR(200),
    fecha_registro TIMESTAMP DEFAULT NOW(),
    activo BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE camion (
    id_camion SERIAL PRIMARY KEY,
    transportista_id INTEGER NOT NULL,
    patente VARCHAR(10) NOT NULL UNIQUE,
    marca VARCHAR(50) NOT NULL,
    modelo VARCHAR(50) NOT NULL,
    anio INTEGER NOT NULL CHECK (anio > 1950),
    capacidad_kg NUMERIC NOT NULL CHECK (capacidad_kg > 0),
    capacidad_m3 NUMERIC NOT NULL CHECK (capacidad_m3 > 0),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_camion_transportista FOREIGN KEY (transportista_id) REFERENCES transportista(id_transportista) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE chofer (
    id_chofer SERIAL PRIMARY KEY,
    transportista_id INTEGER NOT NULL,
    rut VARCHAR(12) NOT NULL UNIQUE,
    nombre_completo VARCHAR(150) NOT NULL,
    licencia_conducir VARCHAR(30) NOT NULL,
    fecha_vencimiento_licencia DATE NOT NULL,
    telefono VARCHAR(20) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_chofer_transportista FOREIGN KEY (transportista_id) REFERENCES transportista(id_transportista) ON DELETE CASCADE ON UPDATE CASCADE
);

-- ============================================================================
-- FASE 2B: COMPATIBILIDAD DE FLOTA (N:M CAMION-TIPO_CARGA) -- NUEVO
-- Indica qué tipos de carga puede transportar cada camión (ej: un camión sin
-- refrigeración no debería poder marcar compatibilidad con carga refrigerada;
-- esa regla semántica se deja a nivel de aplicación, la tabla resuelve la
-- cardinalidad N:M que exigía el modelo conceptual).
-- ============================================================================

CREATE TABLE camion_tipo_carga (
    camion_id INTEGER NOT NULL,
    tipo_carga_id INTEGER NOT NULL,
    CONSTRAINT pk_camion_tipo_carga PRIMARY KEY (camion_id, tipo_carga_id),
    CONSTRAINT fk_camiontipocarga_camion FOREIGN KEY (camion_id) REFERENCES camion(id_camion) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_camiontipocarga_tipocarga FOREIGN KEY (tipo_carga_id) REFERENCES tipo_carga(id_tipo_carga) ON DELETE CASCADE ON UPDATE CASCADE
);

COMMENT ON TABLE camion_tipo_carga IS 'Compatibilidad de flota: tipos de carga que cada camión está habilitado para transportar.';

-- ============================================================================
-- FASE 3: LOGÍSTICA GEOGRÁFICA Y TARIFARIA BASE
-- ============================================================================

CREATE TABLE ruta (
    id_ruta SERIAL PRIMARY KEY,
    origen VARCHAR(100) NOT NULL,
    destino VARCHAR(100) NOT NULL,
    distancia_km NUMERIC CHECK (distancia_km > 0),
    cruce_maritimo_id INTEGER,
    CONSTRAINT fk_ruta_cruce_maritimo FOREIGN KEY (cruce_maritimo_id) REFERENCES cruce_maritimo(id_cruce) ON UPDATE CASCADE
);

CREATE TABLE tarifa_referencial (
    id_tarifa SERIAL PRIMARY KEY,
    ruta_id INTEGER NOT NULL,
    tipo_carga_id INTEGER NOT NULL,
    valor NUMERIC NOT NULL CHECK (valor >= 0),
    fecha_vigencia_desde DATE NOT NULL,
    fecha_vigencia_hasta DATE,
    CONSTRAINT fk_tarifa_ruta FOREIGN KEY (ruta_id) REFERENCES ruta(id_ruta) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_tarifa_tipo_carga FOREIGN KEY (tipo_carga_id) REFERENCES tipo_carga(id_tipo_carga) ON DELETE CASCADE ON UPDATE CASCADE
);

-- ============================================================================
-- FASE 4: FLUJO OPERATIVO (CARGAS Y PUBLICACIONES)
-- ============================================================================

CREATE TABLE carga (
    id_carga SERIAL PRIMARY KEY,
    cliente_id INTEGER NOT NULL,
    tipo_carga_id INTEGER NOT NULL,
    descripcion VARCHAR(300) NOT NULL,
    peso_kg NUMERIC NOT NULL CHECK (peso_kg > 0),
    volumen_m3 NUMERIC NOT NULL CHECK (volumen_m3 > 0),
    valor_declarado NUMERIC CHECK (valor_declarado >= 0),
    fecha_registro TIMESTAMP DEFAULT NOW(),
    CONSTRAINT fk_carga_cliente FOREIGN KEY (cliente_id) REFERENCES cliente(id_cliente) ON UPDATE CASCADE,
    CONSTRAINT fk_carga_tipo_carga FOREIGN KEY (tipo_carga_id) REFERENCES tipo_carga(id_tipo_carga) ON UPDATE CASCADE
);

CREATE TABLE publicacion_carga (
    id_publicacion SERIAL PRIMARY KEY,
    carga_id INTEGER NOT NULL UNIQUE,
    ruta_id INTEGER NOT NULL,
    fecha_publicacion TIMESTAMP DEFAULT NOW(),
    fecha_limite_postulacion DATE NOT NULL,
    tarifa_ofrecida NUMERIC NOT NULL CHECK (tarifa_ofrecida > 0),
    estado VARCHAR(20) NOT NULL DEFAULT 'Disponible',
    CONSTRAINT fk_publicacion_carga FOREIGN KEY (carga_id) REFERENCES carga(id_carga) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_publicacion_ruta FOREIGN KEY (ruta_id) REFERENCES ruta(id_ruta) ON UPDATE CASCADE
);

-- ============================================================================
-- FASE 4B: PUBLICACIÓN DEL LADO TRANSPORTISTA -- NUEVO
-- Entidad que faltaba en la entrega original. Es el espejo de
-- PUBLICACION_CARGA pero desde el transportista: le permite ofrecer
-- capacidad disponible en un camión/ruta/ventana de fechas, habilitando
-- el marketplace de "carga de retorno" en la dirección que faltaba.
-- ============================================================================

CREATE TABLE publicacion_transporte (
    id_publicacion_transporte SERIAL PRIMARY KEY,
    transportista_id INTEGER NOT NULL,
    camion_id INTEGER NOT NULL,
    ruta_id INTEGER NOT NULL,
    fecha_publicacion TIMESTAMP DEFAULT NOW(),
    fecha_disponible_desde DATE NOT NULL,
    fecha_disponible_hasta DATE NOT NULL,
    capacidad_disponible_kg NUMERIC NOT NULL CHECK (capacidad_disponible_kg > 0),
    capacidad_disponible_m3 NUMERIC NOT NULL CHECK (capacidad_disponible_m3 > 0),
    tarifa_referencial_ofrecida NUMERIC CHECK (tarifa_referencial_ofrecida >= 0),
    estado VARCHAR(20) NOT NULL DEFAULT 'Disponible',
    CONSTRAINT fk_publicaciontransporte_transportista FOREIGN KEY (transportista_id) REFERENCES transportista(id_transportista) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_publicaciontransporte_camion FOREIGN KEY (camion_id) REFERENCES camion(id_camion) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_publicaciontransporte_ruta FOREIGN KEY (ruta_id) REFERENCES ruta(id_ruta) ON UPDATE CASCADE,
    CONSTRAINT chk_publicaciontransporte_fechas CHECK (fecha_disponible_hasta > fecha_disponible_desde),
    CONSTRAINT chk_publicaciontransporte_estado CHECK (estado IN ('Disponible','Reservada','Expirada','Cancelada'))
);

COMMENT ON TABLE publicacion_transporte IS 'Publicación de capacidad disponible por parte del transportista (lado espejo de publicacion_carga); habilita el marketplace de carga de retorno en ambas direcciones.';

-- ============================================================================
-- FASE 5: POSTULACIÓN, NEGOCIACIÓN Y MATCHING N:M
-- ============================================================================

CREATE TABLE postulacion (
    id_postulacion SERIAL PRIMARY KEY,
    publicacion_id INTEGER NOT NULL,
    transportista_id INTEGER NOT NULL,
    fecha_postulacion TIMESTAMP DEFAULT NOW(),
    tarifa_propuesta NUMERIC NOT NULL CHECK (tarifa_propuesta > 0),
    estado VARCHAR(20) NOT NULL DEFAULT 'Pendiente',
    comentario VARCHAR(500),
    CONSTRAINT fk_postulacion_publicacion FOREIGN KEY (publicacion_id) REFERENCES publicacion_carga(id_publicacion) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_postulacion_transportista FOREIGN KEY (transportista_id) REFERENCES transportista(id_transportista) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE match (
    id_match SERIAL PRIMARY KEY,
    postulacion_id INTEGER NOT NULL UNIQUE,
    camion_id INTEGER NOT NULL,
    chofer_id INTEGER NOT NULL,
    fecha_match TIMESTAMP DEFAULT NOW(),
    estado VARCHAR(20) NOT NULL DEFAULT 'Confirmado',
    CONSTRAINT fk_match_postulacion FOREIGN KEY (postulacion_id) REFERENCES postulacion(id_postulacion) ON UPDATE CASCADE,
    CONSTRAINT fk_match_camion FOREIGN KEY (camion_id) REFERENCES camion(id_camion) ON UPDATE CASCADE,
    CONSTRAINT fk_match_chofer FOREIGN KEY (chofer_id) REFERENCES chofer(id_chofer) ON UPDATE CASCADE
);

-- ============================================================================
-- FASE 6: EJECUCIÓN DEL VIAJE Y DESNORMALIZACIÓN HISTÓRICA
-- ============================================================================

CREATE TABLE viaje (
    id_viaje SERIAL PRIMARY KEY,
    match_id INTEGER NOT NULL UNIQUE,
    fecha_inicio TIMESTAMP NOT NULL,
    fecha_fin TIMESTAMP,
    estado VARCHAR(20) NOT NULL DEFAULT 'En Progreso',

    -- VALOR HISTÓRICO DESNORMALIZADO (Requisito del enunciado para congelar tarifa)
    tarifa_final NUMERIC NOT NULL CHECK (tarifa_final >= 0),

    CONSTRAINT fk_viaje_match FOREIGN KEY (match_id) REFERENCES match(id_match) ON UPDATE CASCADE
);

COMMENT ON TABLE viaje IS 'Registra la ejecución física de los trayectos logísticos y cruces marítimos.';
COMMENT ON COLUMN viaje.tarifa_final IS 'VALOR HISTÓRICO DESNORMALIZADO: Almacena de forma estática la tarifa final para proteger el registro de fluctuaciones inflacionarias.';

-- ============================================================================
-- FASE 7: INTERACCIONES, ALERTAS Y REGISTROS HISTÓRICOS
-- ============================================================================

CREATE TABLE calificacion (
    id_calificacion SERIAL PRIMARY KEY,
    viaje_id INTEGER NOT NULL,
    emisor VARCHAR(20) NOT NULL,
    puntaje INTEGER NOT NULL CHECK (puntaje BETWEEN 1 AND 5),
    comentario VARCHAR(500),
    fecha_calificacion TIMESTAMP DEFAULT NOW(),
    CONSTRAINT fk_calificacion_viaje FOREIGN KEY (viaje_id) REFERENCES viaje(id_viaje) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE comunicacion (
    id_comunicacion SERIAL PRIMARY KEY,
    postulacion_id INTEGER NOT NULL,
    emisor VARCHAR(20) NOT NULL,
    mensaje VARCHAR(1000) NOT NULL,
    fecha_envio TIMESTAMP DEFAULT NOW(),
    leido BOOLEAN DEFAULT FALSE,
    CONSTRAINT fk_comunicacion_postulacion FOREIGN KEY (postulacion_id) REFERENCES postulacion(id_postulacion) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE historial_cumplimiento (
    id_historial SERIAL PRIMARY KEY,
    viaje_id INTEGER NOT NULL,
    tipo_evento VARCHAR(50) NOT NULL,
    descripcion VARCHAR(500),
    fecha_evento TIMESTAMP DEFAULT NOW(),
    CONSTRAINT fk_historial_viaje FOREIGN KEY (viaje_id) REFERENCES viaje(id_viaje) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE notificacion (
    id_notificacion SERIAL PRIMARY KEY,
    cliente_id INTEGER,
    transportista_id INTEGER,
    tipo_notificacion VARCHAR(50) NOT NULL,
    mensaje VARCHAR(500) NOT NULL,
    fecha_envio TIMESTAMP DEFAULT NOW(),
    leida BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT fk_notificacion_cliente FOREIGN KEY (cliente_id) REFERENCES cliente(id_cliente) ON DELETE CASCADE,
    CONSTRAINT fk_notificacion_transportista FOREIGN KEY (transportista_id) REFERENCES transportista(id_transportista) ON DELETE CASCADE
);

-- ============================================================================
-- FASE 8: ENDURECIMIENTO -- NUEVO
-- Reglas de negocio de dominio, coherencia, unicidad y no solapamiento
-- (sección 3 del informe de evaluación), probadas contra bd_grupo2_sincrochiloe.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 8.1 Extensión requerida para EXCLUDE con igualdad + rangos
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ----------------------------------------------------------------------------
-- 8.2 CHECK de dominio (conjuntos de estado / emisor válidos)
-- ----------------------------------------------------------------------------
ALTER TABLE publicacion_carga
  ADD CONSTRAINT chk_publicacion_estado
  CHECK (estado IN ('Disponible','Asignada','Expirada','Cancelada'));

ALTER TABLE postulacion
  ADD CONSTRAINT chk_postulacion_estado
  CHECK (estado IN ('Pendiente','Aceptada','Rechazada'));

ALTER TABLE match
  ADD CONSTRAINT chk_match_estado
  CHECK (estado IN ('Confirmado','Cancelado','Completado'));

ALTER TABLE viaje
  ADD CONSTRAINT chk_viaje_estado
  CHECK (estado IN ('En Progreso','Completado','Cancelado','Incidencia'));

ALTER TABLE calificacion
  ADD CONSTRAINT chk_calificacion_emisor
  CHECK (emisor IN ('Cliente','Transportista'));

ALTER TABLE comunicacion
  ADD CONSTRAINT chk_comunicacion_emisor
  CHECK (emisor IN ('Cliente','Transportista'));

-- tipo_evento acotado: la consulta 9 depende de que 'Retraso' e 'Incidencia'
-- se escriban siempre igual; sin este CHECK, texto libre podía romper el filtro.
ALTER TABLE historial_cumplimiento
  ADD CONSTRAINT chk_historial_tipo_evento
  CHECK (tipo_evento IN ('Inicio de viaje','Entrega a tiempo','Entrega completada','Retraso','Incidencia','Cancelacion'));

-- ----------------------------------------------------------------------------
-- 8.3 CHECK de coherencia
-- ----------------------------------------------------------------------------
ALTER TABLE viaje
  ADD CONSTRAINT chk_viaje_fechas_coherentes
  CHECK (fecha_fin IS NULL OR fecha_fin > fecha_inicio);

ALTER TABLE tarifa_referencial
  ADD CONSTRAINT chk_tarifa_vigencia_coherente
  CHECK (fecha_vigencia_hasta IS NULL OR fecha_vigencia_hasta > fecha_vigencia_desde);

ALTER TABLE publicacion_carga
  ADD CONSTRAINT chk_publicacion_fechas_coherentes
  CHECK (fecha_limite_postulacion >= fecha_publicacion::date);

ALTER TABLE notificacion
  ADD CONSTRAINT chk_notificacion_destinatario
  CHECK (cliente_id IS NOT NULL OR transportista_id IS NOT NULL);

-- ----------------------------------------------------------------------------
-- 8.4 UNIQUE
-- ----------------------------------------------------------------------------
ALTER TABLE postulacion
  ADD CONSTRAINT uq_postulacion_publicacion_transportista
  UNIQUE (publicacion_id, transportista_id);

-- ----------------------------------------------------------------------------
-- 8.5 EXCLUDE: no solapamiento de tarifa referencial
-- ----------------------------------------------------------------------------
-- Sin tarifas vigentes solapadas para la misma ruta + tipo de carga
ALTER TABLE tarifa_referencial
  ADD CONSTRAINT excl_tarifa_ruta_tipo_sin_solape
  EXCLUDE USING gist (
    ruta_id WITH =,
    tipo_carga_id WITH =,
    daterange(fecha_vigencia_desde,
              COALESCE(fecha_vigencia_hasta, 'infinity'::date), '[)') WITH &&
  );

-- ----------------------------------------------------------------------------
-- 8.6 EXCLUDE: no solapamiento de camión y chofer (vía columnas espejo + trigger)
-- ----------------------------------------------------------------------------
-- El rango temporal vive en VIAJE; camion_id/chofer_id viven en MATCH.
-- Se copian a VIAJE vía trigger para poder construir el EXCLUDE
-- sobre la propia tabla VIAJE.
ALTER TABLE viaje ADD COLUMN camion_id_actual INTEGER;
ALTER TABLE viaje ADD COLUMN chofer_id_actual INTEGER;

CREATE OR REPLACE FUNCTION sync_actores_viaje() RETURNS TRIGGER AS $$
BEGIN
  SELECT camion_id, chofer_id
    INTO NEW.camion_id_actual, NEW.chofer_id_actual
    FROM match WHERE id_match = NEW.match_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_actores_viaje
  BEFORE INSERT OR UPDATE OF match_id ON viaje
  FOR EACH ROW EXECUTE FUNCTION sync_actores_viaje();

ALTER TABLE viaje
  ADD CONSTRAINT excl_viaje_camion_sin_solape
  EXCLUDE USING gist (
    camion_id_actual WITH =,
    tsrange(fecha_inicio, COALESCE(fecha_fin, 'infinity'::timestamp)) WITH &&
  ) WHERE (estado <> 'Cancelado');

ALTER TABLE viaje
  ADD CONSTRAINT excl_viaje_chofer_sin_solape
  EXCLUDE USING gist (
    chofer_id_actual WITH =,
    tsrange(fecha_inicio, COALESCE(fecha_fin, 'infinity'::timestamp)) WITH &&
  ) WHERE (estado <> 'Cancelado');

-- ============================================================================
-- FASE 9: INSERCIÓN DE DATOS DE PRUEBA
-- Datos ficticios ambientados en el corredor logístico de Chiloé, pensados
-- para poder ejecutar y comprobar cada constraint (CHECK, UNIQUE, EXCLUDE,
-- FK) y para dejar cubiertas las 10 consultas de la sección siguiente.
-- ============================================================================

-- 9.1 Maestras generales -----------------------------------------------------
INSERT INTO tipo_cliente (nombre_tipo, descripcion) VALUES
('Empresa', 'Persona jurídica que contrata transporte de carga'),
('Persona Natural', 'Cliente individual que contrata transporte de carga');

INSERT INTO tipo_carga (nombre, requiere_refrigeracion, es_peligrosa, descripcion) VALUES
('Carga General', FALSE, FALSE, 'Mercadería general sin requisitos especiales'),
('Perecederos', TRUE, FALSE, 'Productos que requieren cadena de frío'),
('Materiales Peligrosos', FALSE, TRUE, 'Combustibles, químicos u otros materiales peligrosos'),
('Carga Seca a Granel', FALSE, FALSE, 'Granos, áridos u otra carga seca sin embalaje individual');

INSERT INTO cruce_maritimo (nombre, empresa_naviera, duracion_estimada_min, tarifa_cruce) VALUES
('Pargua - Chacao', 'Naviera Cruz del Sur', 30, 8000),
('Chonchi - Quellón', 'Naviera Austral', 45, 12000);

-- 9.2 Actores -----------------------------------------------------------------
INSERT INTO cliente (tipo_cliente_id, rut, nombre_razon_social, email, telefono, direccion, comuna) VALUES
(1, '76111222-3', 'Agrícola Chiloé Ltda', 'contacto@agrichiloe.cl', '+56912345671', 'Camino Rural Km 5', 'Castro'),
(1, '76222333-4', 'Pesquera Los Lagos SpA', 'ventas@pesquerallagos.cl', '+56912345672', 'Costanera 450', 'Quellón'),
(2, '12345678-9', 'Juan Pérez Soto', 'juan.perez@gmail.com', '+56912345673', 'Los Alerces 120', 'Ancud'),
(1, '76333444-5', 'Distribuidora Ancud', 'contacto@distribancud.cl', '+56912345674', 'Av. Errázuriz 800', 'Ancud');

INSERT INTO transportista (rut_empresa, razon_social, email, telefono, direccion) VALUES
('76444555-6', 'Transportes Castro Ltda', 'operaciones@transcastro.cl', '+56922345671', 'Panamericana Sur 1200'),
('76555666-7', 'Fletes del Sur SpA', 'contacto@fletesdelsur.cl', '+56922345672', 'Camino a Chacao 300'),
('76666777-8', 'Logística Quellón EIRL', 'info@logisticaquellon.cl', '+56922345673', 'Ruta 5 Km 220');

INSERT INTO camion (transportista_id, patente, marca, modelo, anio, capacidad_kg, capacidad_m3, activo) VALUES
(1, 'AB1234', 'Volvo', 'FH440', 2019, 8000, 40, TRUE),
(1, 'AB5678', 'Mercedes-Benz', 'Actros Frío', 2021, 5000, 25, TRUE),
(2, 'CD1122', 'Scania', 'R450', 2018, 9000, 45, TRUE),
(3, 'EF3344', 'Hino', '500 Series', 2020, 4000, 20, TRUE);

INSERT INTO chofer (transportista_id, rut, nombre_completo, licencia_conducir, fecha_vencimiento_licencia, telefono) VALUES
(1, '15111222-3', 'Pedro Aguilar Muñoz', 'A5-12345', '2027-05-10', '+56933345671'),
(1, '15222333-4', 'Marcelo Vidal Torres', 'A5-23456', '2026-12-20', '+56933345672'),
(2, '15333444-5', 'Ricardo Barría Soto', 'A5-34567', '2027-03-15', '+56933345673'),
(3, '15444555-6', 'Cristián Mansilla Paredes', 'A5-45678', '2028-01-30', '+56933345674');

-- 9.3 Compatibilidad de flota N:M (NUEVO) --------------------------------------
INSERT INTO camion_tipo_carga (camion_id, tipo_carga_id) VALUES
(1, 1), (1, 4),           -- camión 1: carga general y seca a granel
(2, 2),                   -- camión 2: refrigerado -> perecederos
(3, 1), (3, 3),           -- camión 3: general y peligrosa
(4, 1);                   -- camión 4: general

-- 9.4 Logística geográfica y tarifaria base ------------------------------------
INSERT INTO ruta (origen, destino, distancia_km, cruce_maritimo_id) VALUES
('Puerto Montt', 'Castro', 220, 1),   -- 1: cruza por Pargua-Chacao
('Castro', 'Quellón', 95, NULL),      -- 2: sin cruce marítimo
('Ancud', 'Castro', 90, NULL),        -- 3: sin cruce marítimo
('Puerto Montt', 'Quellón', 300, 1);  -- 4: también cruza Pargua-Chacao

-- Tarifas referenciales: se dejan dos vigencias consecutivas para ruta 1 +
-- tipo 1 (sin solape) para poder mostrar el EXCLUDE en acción si se intenta
-- insertar una tercera que se traslape.
INSERT INTO tarifa_referencial (ruta_id, tipo_carga_id, valor, fecha_vigencia_desde, fecha_vigencia_hasta) VALUES
(1, 1, 140000, '2026-01-01', '2026-06-30'),  -- vigencia antigua ruta1+tipo1
(1, 1, 155000, '2026-07-01', NULL),          -- vigencia actual ruta1+tipo1
(1, 2, 180000, '2026-01-01', NULL),          -- ruta1+tipo2 (perecederos)
(1, 3, 300000, '2026-01-01', NULL),          -- ruta1+tipo3 (peligrosa)
(3, 1, 60000, '2026-01-01', NULL),           -- ruta3+tipo1
(2, 1, 70000, '2026-01-01', NULL);           -- ruta2+tipo1

-- 9.5 Cargas y publicaciones ----------------------------------------------------
INSERT INTO carga (cliente_id, tipo_carga_id, descripcion, peso_kg, volumen_m3, valor_declarado) VALUES
(1, 1, 'Pallets de papas embaladas', 6000, 18, 2500000),
(2, 2, 'Cajas de salmón fresco refrigerado', 4200, 12, 8000000),
(3, 1, 'Muebles de madera nativa', 1800, 10, 1200000),
(4, 3, 'Bidones de combustible industrial', 3000, 8, 3500000),
(1, 1, 'Sacos de harina', 5000, 15, 1800000);

INSERT INTO publicacion_carga (carga_id, ruta_id, fecha_publicacion, fecha_limite_postulacion, tarifa_ofrecida, estado) VALUES
(1, 1, '2026-06-20 09:00', '2026-07-05', 150000, 'Asignada'),
(2, 1, '2026-06-25 10:00', '2026-07-03', 200000, 'Asignada'),
(3, 3, '2026-07-01 11:00', '2026-07-20', 90000, 'Disponible'),
(4, 1, '2026-06-22 08:00', '2026-07-08', 250000, 'Asignada'),
(5, 2, '2026-07-05 09:00', '2026-07-25', 80000, 'Disponible');

-- 9.6 Publicación del lado transportista (NUEVO) -------------------------------
INSERT INTO publicacion_transporte (transportista_id, camion_id, ruta_id, fecha_disponible_desde, fecha_disponible_hasta, capacidad_disponible_kg, capacidad_disponible_m3, tarifa_referencial_ofrecida, estado) VALUES
(2, 3, 2, '2026-07-15', '2026-07-20', 6000, 30, 65000, 'Disponible'),
(3, 4, 3, '2026-07-18', '2026-07-25', 3500, 18, 55000, 'Disponible'),
(1, 1, 1, '2026-07-01', '2026-07-10', 7000, 35, 145000, 'Reservada');

-- 9.7 Postulación, negociación y matching N:M -----------------------------------
INSERT INTO postulacion (publicacion_id, transportista_id, tarifa_propuesta, estado, comentario) VALUES
(1, 1, 145000, 'Aceptada', 'Disponemos de camión y chofer para esa fecha'),
(1, 2, 148000, 'Rechazada', 'Llegamos tarde a la oferta'),
(2, 1, 195000, 'Aceptada', 'Podemos cubrir la ruta con camión refrigerado'),
(4, 2, 240000, 'Aceptada', 'Manejamos materiales peligrosos con certificación'),
(3, 3, 85000, 'Pendiente', NULL),
(5, 3, 78000, 'Pendiente', NULL);

INSERT INTO match (postulacion_id, camion_id, chofer_id, estado) VALUES
(1, 1, 1, 'Confirmado'),  -- publicación 1 (carga papas) -> transportista 1
(3, 1, 2, 'Confirmado'),  -- publicación 2 (salmón) -> transportista 1, otro chofer/fecha
(4, 3, 3, 'Confirmado');  -- publicación 4 (combustible) -> transportista 2

-- 9.8 Ejecución del viaje (el trigger sync_actores_viaje copia camión/chofer
-- desde MATCH automáticamente al insertar) --------------------------------------
INSERT INTO viaje (match_id, fecha_inicio, fecha_fin, estado, tarifa_final) VALUES
(1, '2026-07-02 08:00', '2026-07-02 14:00', 'Completado', 145000),
(2, '2026-07-06 08:00', '2026-07-06 15:00', 'Completado', 195000),
(3, '2026-07-09 07:00', NULL, 'En Progreso', 240000);

-- 9.9 Interacciones, alertas e historial -----------------------------------------
INSERT INTO calificacion (viaje_id, emisor, puntaje, comentario) VALUES
(1, 'Cliente', 5, 'Entrega puntual y en buen estado'),
(1, 'Transportista', 4, 'Carga bien embalada, sin problemas'),
(2, 'Cliente', 3, 'Hubo un retraso en la entrega');

INSERT INTO comunicacion (postulacion_id, emisor, mensaje, leido) VALUES
(1, 'Transportista', 'Confirmo disponibilidad para el viaje', TRUE),
(1, 'Cliente', 'Perfecto, esperamos el camión el día acordado', TRUE),
(5, 'Transportista', '¿Sigue disponible la carga hacia Castro?', FALSE);

INSERT INTO historial_cumplimiento (viaje_id, tipo_evento, descripcion) VALUES
(1, 'Entrega a tiempo', 'Carga entregada dentro del horario acordado'),
(2, 'Retraso', 'El camión llegó 3 horas tarde por mal tiempo en el cruce Pargua-Chacao'),
(3, 'Inicio de viaje', 'Viaje iniciado según lo programado');

INSERT INTO notificacion (cliente_id, transportista_id, tipo_notificacion, mensaje) VALUES
(1, NULL, 'publicacion_asignada', 'Su carga fue asignada a un transportista'),
(NULL, 1, 'nuevo_match', 'Ha sido asignado a un nuevo viaje'),
(2, NULL, 'postulacion_recibida', 'Recibió una postulación para su publicación de carga');


-- ============================================================================
-- FASE 10: CONSULTAS (10 consultas del enunciado, traducidas a SQL)
-- ============================================================================

-- 1. ¿Qué publicaciones de carga están disponibles y cuál es su tarifa ofrecida?
SELECT
    pc.id_publicacion,
    c.descripcion            AS carga,
    pc.tarifa_ofrecida,
    pc.estado
FROM publicacion_carga pc
JOIN carga c ON c.id_carga = pc.carga_id
WHERE pc.estado = 'Disponible';

-- 2. ¿Qué transportistas están activos actualmente?
SELECT
    t.id_transportista,
    t.razon_social,
    t.email
FROM transportista t
WHERE t.activo = TRUE;

-- 3. Para cada publicación de carga, ¿quién es el cliente, cuál es la ruta y
--    qué tipo de carga es?
SELECT
    pc.id_publicacion,
    cli.nombre_razon_social   AS cliente,
    r.origen || ' - ' || r.destino AS ruta,
    tc.nombre                 AS tipo_carga
FROM publicacion_carga pc
JOIN carga c        ON c.id_carga = pc.carga_id
JOIN cliente cli    ON cli.id_cliente = c.cliente_id
JOIN ruta r          ON r.id_ruta = pc.ruta_id
JOIN tipo_carga tc   ON tc.id_tipo_carga = c.tipo_carga_id;

-- 4. ¿Cuántas postulaciones ha recibido cada publicación de carga?
SELECT
    pc.id_publicacion,
    c.descripcion AS carga,
    COUNT(p.id_postulacion) AS total_postulaciones
FROM publicacion_carga pc
JOIN carga c ON c.id_carga = pc.carga_id
LEFT JOIN postulacion p ON p.publicacion_id = pc.id_publicacion
GROUP BY pc.id_publicacion, c.descripcion
ORDER BY pc.id_publicacion;

-- 5. Para cada viaje, ¿qué transportista, camión y chofer están involucrados?
SELECT
    v.id_viaje,
    t.razon_social      AS transportista,
    ca.patente          AS camion,
    ch.nombre_completo   AS chofer
FROM viaje v
JOIN match m      ON m.id_match = v.match_id
JOIN camion ca    ON ca.id_camion = m.camion_id
JOIN chofer ch    ON ch.id_chofer = m.chofer_id
JOIN transportista t ON t.id_transportista = ca.transportista_id;

-- 6. ¿Cuál es el puntaje promedio de calificación de cada transportista?
SELECT
    t.id_transportista,
    t.razon_social,
    ROUND(AVG(cal.puntaje), 2) AS puntaje_promedio
FROM transportista t
JOIN camion ca            ON ca.transportista_id = t.id_transportista
JOIN match m               ON m.camion_id = ca.id_camion
JOIN viaje v                ON v.match_id = m.id_match
JOIN calificacion cal       ON cal.viaje_id = v.id_viaje
WHERE cal.emisor = 'Cliente'   -- puntaje que el cliente le da al transportista
GROUP BY t.id_transportista, t.razon_social;

-- 7. ¿Cuál es el ranking de transportistas según sus ingresos totales (suma de
--    la tarifa final de todos sus viajes)?
SELECT
    t.id_transportista,
    t.razon_social,
    SUM(v.tarifa_final) AS ingresos_totales,
    RANK() OVER (ORDER BY SUM(v.tarifa_final) DESC) AS ranking
FROM transportista t
JOIN camion ca  ON ca.transportista_id = t.id_transportista
JOIN match m    ON m.camion_id = ca.id_camion
JOIN viaje v    ON v.match_id = m.id_match
GROUP BY t.id_transportista, t.razon_social
ORDER BY ranking;

-- 8. Para cada ruta y tipo de carga, ¿cuál es la tarifa referencial vigente
--    hoy, y cómo se compara contra el promedio real cobrado en los viajes de
--    esa combinación?
SELECT
    r.id_ruta,
    r.origen || ' - ' || r.destino AS ruta,
    tc.nombre                     AS tipo_carga,
    tarifa_vig.valor               AS tarifa_referencial_vigente,
    ROUND(AVG(v.tarifa_final), 2)  AS promedio_real_cobrado,
    ROUND(AVG(v.tarifa_final) - tarifa_vig.valor, 2) AS diferencia
FROM tarifa_referencial tarifa_vig
JOIN ruta r        ON r.id_ruta = tarifa_vig.ruta_id
JOIN tipo_carga tc ON tc.id_tipo_carga = tarifa_vig.tipo_carga_id
JOIN carga c        ON c.tipo_carga_id = tarifa_vig.tipo_carga_id
JOIN publicacion_carga pc ON pc.carga_id = c.id_carga AND pc.ruta_id = tarifa_vig.ruta_id
JOIN postulacion p  ON p.publicacion_id = pc.id_publicacion AND p.estado = 'Aceptada'
JOIN match m         ON m.postulacion_id = p.id_postulacion
JOIN viaje v          ON v.match_id = m.id_match
WHERE tarifa_vig.fecha_vigencia_desde <= CURRENT_DATE
  AND (tarifa_vig.fecha_vigencia_hasta IS NULL OR tarifa_vig.fecha_vigencia_hasta >= CURRENT_DATE)
GROUP BY r.id_ruta, r.origen, r.destino, tc.nombre, tarifa_vig.valor;

-- 9. ¿Qué transportistas presentan eventos de retraso o incidente en más del
--    30% de sus viajes?
SELECT
    t.id_transportista,
    t.razon_social,
    COUNT(DISTINCT v.id_viaje)                                        AS total_viajes,
    COUNT(DISTINCT hc.viaje_id)                                       AS viajes_con_evento,
    ROUND(100.0 * COUNT(DISTINCT hc.viaje_id) / COUNT(DISTINCT v.id_viaje), 1) AS porcentaje_eventos
FROM transportista t
JOIN camion ca ON ca.transportista_id = t.id_transportista
JOIN match m   ON m.camion_id = ca.id_camion
JOIN viaje v   ON v.match_id = m.id_match
LEFT JOIN historial_cumplimiento hc
    ON hc.viaje_id = v.id_viaje
    AND hc.tipo_evento IN ('Retraso', 'Incidencia')
GROUP BY t.id_transportista, t.razon_social
HAVING 100.0 * COUNT(DISTINCT hc.viaje_id) / COUNT(DISTINCT v.id_viaje) > 30;

-- 10. ¿Qué clientes tuvieron cargas cuyo viaje terminó más de 2 días después
--     del plazo límite de postulación?
SELECT DISTINCT
    cli.id_cliente,
    cli.nombre_razon_social AS cliente,
    c.descripcion            AS carga,
    pc.fecha_limite_postulacion,
    v.fecha_fin
FROM cliente cli
JOIN carga c              ON c.cliente_id = cli.id_cliente
JOIN publicacion_carga pc ON pc.carga_id = c.id_carga
JOIN postulacion p         ON p.publicacion_id = pc.id_publicacion AND p.estado = 'Aceptada'
JOIN match m                ON m.postulacion_id = p.id_postulacion
JOIN viaje v                 ON v.match_id = m.id_match
WHERE v.fecha_fin IS NOT NULL
  AND v.fecha_fin::date - pc.fecha_limite_postulacion > 2;


-- ============================================================================
-- FIN DEL SCRIPT
-- ============================================================================