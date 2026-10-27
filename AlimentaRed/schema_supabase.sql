-- ============================================================================
-- PROYECTO: AlimentaRed - Plataforma de Rescate y Distribución Responsable de Alimentos
-- MOTOR: PostgreSQL 15+ / Supabase
-- INTEGRIDAD: Compatible 100% con JPA / Spring Boot y Tercera Forma Normal (3FN)
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Limpieza preventiva
DROP VIEW IF EXISTS v_indicadores_impacto CASCADE;
DROP VIEW IF EXISTS v_lotes_disponibles CASCADE;
DROP VIEW IF EXISTS usuarios CASCADE;
DROP VIEW IF EXISTS categoria_alimento CASCADE;

DROP TABLE IF EXISTS historial_estado CASCADE;
DROP TABLE IF EXISTS strike CASCADE;
DROP TABLE IF EXISTS incidencia CASCADE;
DROP TABLE IF EXISTS entrega CASCADE;
DROP TABLE IF EXISTS asignacion CASCADE;
DROP TABLE IF EXISTS solicitud CASCADE;
DROP TABLE IF EXISTS lote CASCADE;
DROP TABLE IF EXISTS tipo_alimento CASCADE;
DROP TABLE IF EXISTS usuario CASCADE;
DROP TABLE IF EXISTS organizacion CASCADE;

-- ============================================================================
-- 1. ENTIDADES BASE Y ACCESOS
-- ============================================================================

CREATE TABLE organizacion (
    id_organizacion BIGSERIAL PRIMARY KEY,
    nit VARCHAR(20) NOT NULL UNIQUE,
    nombre VARCHAR(150) NOT NULL,
    ubicacion VARCHAR(200),
    correo VARCHAR(150) NOT NULL,
    telefono VARCHAR(30),
    verificada BOOLEAN NOT NULL DEFAULT FALSE,
    bloqueada BOOLEAN NOT NULL DEFAULT FALSE,
    strikes_vigentes INTEGER NOT NULL DEFAULT 0 CHECK (strikes_vigentes >= 0),
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX idx_organizacion_nit ON organizacion(nit);
CREATE INDEX idx_organizacion_bloqueada ON organizacion(bloqueada);

CREATE TABLE usuario (
    id_usuario BIGSERIAL PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    correo VARCHAR(150) NOT NULL UNIQUE,
    contrasena VARCHAR(255) NOT NULL,
    rol VARCHAR(20) NOT NULL CHECK (rol IN ('DONANTE', 'RECEPTORA', 'COORDINADOR', 'ADMINISTRADOR')),
    organizacion_id BIGINT NULL REFERENCES organizacion(id_organizacion) ON DELETE SET NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_usuario_correo ON usuario(correo);
CREATE INDEX idx_usuario_rol ON usuario(rol);
CREATE INDEX idx_usuario_org ON usuario(organizacion_id);

-- Vista de compatibilidad para usuarios (plural)
CREATE OR REPLACE VIEW usuarios AS 
SELECT id_usuario, nombre, correo, contrasena AS password_hash, rol, organizacion_id, activo, fecha_registro 
FROM usuario;

-- ============================================================================
-- 2. CATÁLOGO E INVENTARIO
-- ============================================================================

CREATE TABLE tipo_alimento (
    id_categoria BIGSERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion VARCHAR(300),
    unidad_medida VARCHAR(20) NOT NULL
);

-- Vista de compatibilidad para categoria_alimento
CREATE OR REPLACE VIEW categoria_alimento AS 
SELECT id_categoria, nombre, descripcion, unidad_medida FROM tipo_alimento;

CREATE TABLE lote (
    id_lote BIGSERIAL PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    descripcion VARCHAR(500) NOT NULL,
    categoria_id BIGINT NOT NULL REFERENCES tipo_alimento(id_categoria) ON UPDATE CASCADE,
    donante_id BIGINT NOT NULL REFERENCES organizacion(id_organizacion) ON DELETE RESTRICT,
    cantidad_inicial NUMERIC(12,3) NOT NULL CHECK (cantidad_inicial > 0),
    cantidad_disponible NUMERIC(12,3) NOT NULL CHECK (cantidad_disponible >= 0),
    unidad_minima NUMERIC(12,3) NOT NULL CHECK (unidad_minima > 0),
    multiplo NUMERIC(12,3) NOT NULL DEFAULT 1.000 CHECK (multiplo > 0),
    estado VARCHAR(20) NOT NULL DEFAULT 'DISPONIBLE' CHECK (estado IN ('BORRADOR', 'DISPONIBLE', 'ASIGNADO', 'ENTREGADO', 'INCIDENCIA', 'CANCELADO', 'VENCIDO')),
    estado_alimento VARCHAR(20) DEFAULT 'FRESCO' CHECK (estado_alimento IN ('FRESCO', 'MEDIO', 'PODRIDO')),
    ubicacion VARCHAR(200),
    instrucciones_recogida VARCHAR(500),
    contacto VARCHAR(150),
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_caducidad TIMESTAMP NOT NULL,
    version BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT chk_lote_disponibilidad CHECK (cantidad_disponible <= cantidad_inicial),
    CONSTRAINT chk_lote_unidad_minima CHECK (unidad_minima <= cantidad_inicial)
);

CREATE INDEX idx_lote_donante ON lote(donante_id);
CREATE INDEX idx_lote_categoria ON lote(categoria_id);
CREATE INDEX idx_lote_estado ON lote(estado);
CREATE INDEX idx_lote_caducidad ON lote(fecha_caducidad);

-- ============================================================================
-- 3. MOTOR TRANSACCIONAL LOGÍSTICO
-- ============================================================================

CREATE TABLE solicitud (
    id_solicitud BIGSERIAL PRIMARY KEY,
    lote_id BIGINT NOT NULL REFERENCES lote(id_lote) ON DELETE CASCADE,
    organizacion_id BIGINT NOT NULL REFERENCES organizacion(id_organizacion) ON DELETE RESTRICT,
    cantidad_solicitada NUMERIC(12,3) NOT NULL CHECK (cantidad_solicitada > 0),
    estado VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE' CHECK (estado IN ('PENDIENTE', 'APROBADO', 'CANCELADO', 'RECHAZADA', 'EXPIRADA', 'COMPLETADA')),
    fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_resolucion TIMESTAMP,
    en_empate BOOLEAN NOT NULL DEFAULT FALSE,
    motivo_resolucion VARCHAR(500),
    version BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX idx_solicitud_lote ON solicitud(lote_id);
CREATE INDEX idx_solicitud_org ON solicitud(organizacion_id);
CREATE INDEX idx_solicitud_estado_fecha ON solicitud(estado, fecha_creacion);

CREATE TABLE asignacion (
    id_asignacion BIGSERIAL PRIMARY KEY,
    solicitud_id BIGINT NOT NULL UNIQUE REFERENCES solicitud(id_solicitud) ON DELETE CASCADE,
    cantidad_asignada NUMERIC(12,3) NOT NULL CHECK (cantidad_asignada > 0),
    cantidad_retirada NUMERIC(12,3) NOT NULL DEFAULT 0.000 CHECK (cantidad_retirada >= 0),
    estado VARCHAR(25) NOT NULL DEFAULT 'ACTIVA' CHECK (estado IN ('ACTIVA', 'RETIRO_PARCIAL', 'COMPLETADA', 'NO_RECOGIDA', 'CANCELADA', 'CERRADA_CON_RESTOCK')),
    auto_asignada BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_asignacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_limite_retiro TIMESTAMP NOT NULL,
    fecha_cierre TIMESTAMP,
    usuario_responsable_id BIGINT NULL REFERENCES usuario(id_usuario),
    version BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT chk_asignacion_retiro_max CHECK (cantidad_retirada <= cantidad_asignada)
);

CREATE INDEX idx_asignacion_solicitud ON asignacion(solicitud_id);
CREATE INDEX idx_asignacion_estado ON asignacion(estado);

CREATE TABLE entrega (
    id_entrega BIGSERIAL PRIMARY KEY,
    solicitud_id BIGINT NOT NULL REFERENCES solicitud(id_solicitud),
    asignacion_id BIGINT NOT NULL REFERENCES asignacion(id_asignacion) ON DELETE CASCADE,
    cantidad_retirada NUMERIC(12,3) NOT NULL CHECK (cantidad_retirada >= 0),
    fecha_entrega TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    observaciones VARCHAR(500),
    usuario_responsable_id BIGINT NOT NULL REFERENCES usuario(id_usuario),
    fuera_de_franja BOOLEAN NOT NULL DEFAULT FALSE,
    estado VARCHAR(20) NOT NULL DEFAULT 'COMPLETA' CHECK (estado IN ('PARCIAL', 'COMPLETA'))
);

CREATE INDEX idx_entrega_asignacion ON entrega(asignacion_id);

-- ============================================================================
-- 4. AUDITORÍA, ANOMALÍAS Y SANCIONES
-- ============================================================================

CREATE TABLE incidencia (
    id_incidencia BIGSERIAL PRIMARY KEY,
    lote_id BIGINT NOT NULL REFERENCES lote(id_lote) ON DELETE CASCADE,
    detalles VARCHAR(500) NOT NULL,
    estado_lote_anterior VARCHAR(20) NOT NULL,
    usuario_reporta_id BIGINT NOT NULL REFERENCES usuario(id_usuario),
    fecha_reporte TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resuelta BOOLEAN NOT NULL DEFAULT FALSE,
    resolucion VARCHAR(500),
    usuario_resuelve_id BIGINT NULL REFERENCES usuario(id_usuario),
    fecha_resolucion TIMESTAMP
);

CREATE INDEX idx_incidencia_lote ON incidencia(lote_id);

CREATE TABLE strike (
    id_strike BIGSERIAL PRIMARY KEY,
    organizacion_id BIGINT NOT NULL REFERENCES organizacion(id_organizacion) ON DELETE RESTRICT,
    asignacion_id BIGINT NULL REFERENCES asignacion(id_asignacion) ON DELETE SET NULL,
    nombre_strike VARCHAR(120) NOT NULL,
    detalles VARCHAR(500),
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    vigente BOOLEAN NOT NULL DEFAULT TRUE,
    justificacion_apelacion VARCHAR(500),
    fecha_apelacion TIMESTAMP,
    usuario_evaluador_id BIGINT NULL REFERENCES usuario(id_usuario)
);

CREATE INDEX idx_strike_org ON strike(organizacion_id);
CREATE INDEX idx_strike_vigente ON strike(organizacion_id, vigente);

CREATE TABLE historial_estado (
    id_historial BIGSERIAL PRIMARY KEY,
    entidad VARCHAR(20) NOT NULL CHECK (entidad IN ('LOTE', 'SOLICITUD', 'ASIGNACION', 'INCIDENCIA', 'ORGANIZACION', 'STRIKE')),
    entidad_id BIGINT NOT NULL,
    estado_anterior VARCHAR(30),
    estado_nuevo VARCHAR(30) NOT NULL,
    usuario_responsable_id BIGINT NULL REFERENCES usuario(id_usuario),
    fecha TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    justificacion VARCHAR(500)
);

CREATE INDEX idx_historial_entidad ON historial_estado(entidad, entidad_id);

-- ============================================================================
-- 5. VISTAS DE NEGOCIO Y PRIVACIDAD (RF04 / RF09)
-- ============================================================================

CREATE OR REPLACE VIEW v_lotes_disponibles AS
SELECT 
    l.id_lote,
    l.nombre,
    l.descripcion,
    t.nombre AS categoria,
    t.unidad_medida,
    o.nombre AS donante_nombre,
    l.ubicacion,
    l.cantidad_disponible,
    l.unidad_minima,
    l.multiplo,
    l.fecha_caducidad,
    CASE 
        WHEN l.fecha_caducidad <= (CURRENT_TIMESTAMP + INTERVAL '4 hours') THEN TRUE 
        ELSE FALSE 
    END AS rescate_urgente
FROM lote l
JOIN tipo_alimento t ON l.categoria_id = t.id_categoria
JOIN organizacion o ON l.donante_id = o.id_organizacion
WHERE l.estado = 'DISPONIBLE'
  AND l.cantidad_disponible > 0
  AND l.fecha_caducidad > CURRENT_TIMESTAMP;

CREATE OR REPLACE VIEW v_indicadores_impacto AS
SELECT
    COALESCE(SUM(e.cantidad_retirada), 0) AS total_alimentos_recuperados,
    COUNT(DISTINCT e.id_entrega) AS total_entregas_completadas,
    COUNT(DISTINCT l.id_lote) AS total_lotes_publicados,
    COUNT(DISTINCT CASE WHEN o.bloqueada = FALSE AND u.rol = 'DONANTE' THEN o.id_organizacion END) AS comercios_activos,
    COUNT(DISTINCT CASE WHEN o.bloqueada = FALSE AND u.rol = 'RECEPTORA' THEN o.id_organizacion END) AS fundaciones_activas,
    COUNT(DISTINCT CASE WHEN s.vigente = TRUE THEN s.id_strike END) AS strikes_vigentes_totales
FROM organizacion o
LEFT JOIN usuario u ON u.organizacion_id = o.id_organizacion
LEFT JOIN lote l ON l.donante_id = o.id_organizacion
LEFT JOIN solicitud sol ON sol.lote_id = l.id_lote
LEFT JOIN asignacion a ON a.solicitud_id = sol.id_solicitud
LEFT JOIN entrega e ON e.asignacion_id = a.id_asignacion
LEFT JOIN strike s ON s.organizacion_id = o.id_organizacion;

-- ============================================================================
-- 6. TRIGGERS DE SUSPENSIÓN AUTOMÁTICA POR STRIKES (RN08 / RN12)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_actualizar_strikes_organizacion()
RETURNS TRIGGER AS $$
DECLARE
    v_conteo_vigentes INTEGER;
    v_id_org BIGINT;
BEGIN
    v_id_org := COALESCE(NEW.organizacion_id, OLD.organizacion_id);
    
    SELECT COUNT(*) INTO v_conteo_vigentes
    FROM strike
    WHERE organizacion_id = v_id_org AND vigente = TRUE;

    UPDATE organizacion
    SET strikes_vigentes = v_conteo_vigentes,
        bloqueada = (v_conteo_vigentes >= 3)
    WHERE id_organizacion = v_id_org;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_actualizar_strikes ON strike;
CREATE TRIGGER trg_actualizar_strikes
AFTER INSERT OR UPDATE OR DELETE ON strike
FOR EACH ROW
EXECUTE FUNCTION fn_actualizar_strikes_organizacion();

-- ============================================================================
-- 7. DATOS INICIALES (SEED DATA CON CONTRASEÑAS BCRYPT FUNCIONALES)
-- ============================================================================

-- Categorías
INSERT INTO tipo_alimento (id_categoria, nombre, descripcion, unidad_medida) VALUES
(1, 'Frutas y verduras', 'Productos frescos de origen vegetal', 'KG'),
(2, 'Panadería', 'Pan, pasteles y productos horneados', 'UNIDAD'),
(3, 'Lácteos', 'Leche, yogures y derivados', 'L'),
(4, 'Proteínas', 'Carnes, pollo, pescado y huevos', 'KG'),
(5, 'Comidas preparadas', 'Platos listos para consumo inmediato', 'PORCION'),
(6, 'Granos y abarrotes', 'Arroz, granos, enlatados y no perecederos', 'KG')
ON CONFLICT (id_categoria) DO UPDATE SET nombre = EXCLUDED.nombre;

ALTER SEQUENCE tipo_alimento_id_categoria_seq RESTART WITH 7;

-- Organizaciones
INSERT INTO organizacion (id_organizacion, nit, nombre, ubicacion, correo, telefono, verificada, bloqueada, strikes_vigentes) VALUES
(1, '901234567-1', 'Restaurante Sabor Casero', 'Centro Histórico, Carrera 7 # 12-40', 'contacto@saborcasero.com', '3101234567', TRUE, FALSE, 0),
(2, '901876543-2', 'Panificadora Central SAS', 'Zona Industrial, Calle 26 # 68-15', 'donaciones@panificadoracentral.com', '3157654321', TRUE, FALSE, 0),
(3, '800987654-3', 'Fundación Pan Compartido', 'Comuna 4, Manzana 12 Casa 5', 'direccion@pancompartido.org', '3209876543', TRUE, FALSE, 0),
(4, '800345678-4', 'Comedor Infantil Esperanza', 'Barrio El Carmen, Transversal 15 # 3-22', 'coordinacion@comedoresperanza.org', '3183456789', TRUE, FALSE, 0),
(5, '800555999-5', 'Hogar Abuelitos de la Paz', 'Barrio San Carlos, Carrera 10 # 45-10', 'contacto@abuelitospaz.org', '3115559999', TRUE, TRUE, 3)
ON CONFLICT (id_organizacion) DO NOTHING;

ALTER SEQUENCE organizacion_id_organizacion_seq RESTART WITH 6;

-- Usuarios (Contraseñas: Admin12345, Coord12345, Pass12345 encriptadas con BCrypt)
INSERT INTO usuario (id_usuario, nombre, correo, contrasena, rol, organizacion_id, activo) VALUES
(1, 'Administrador AlimentaRed', 'admin@alimentared.com', '$2a$10$jdKHXw5XRfrXS7W7242I8eT6qq9wAJX02LM7nXPMzGujziRwahZp6', 'ADMINISTRADOR', NULL, TRUE),
(2, 'Coordinador Red Comunitaria', 'coordinador@alimentared.com', '$2a$10$mH5aZQxfshLlB8XLm6FQNem8OmkyKbgmB/eNZZzMXAhKyIHxJhUwW', 'COORDINADOR', NULL, TRUE),
(3, 'Chef Martín Pérez', 'donante@saborcasero.com', '$2a$10$7HCDGsvQ4XcAdcY8cfYH4OvEUBdo/PFqFhG6oR45qWGnKFLPncenK', 'DONANTE', 1, TRUE),
(4, 'Gerente Panificadora Central', 'donante@panificadoracentral.com', '$2a$10$7HCDGsvQ4XcAdcY8cfYH4OvEUBdo/PFqFhG6oR45qWGnKFLPncenK', 'DONANTE', 2, TRUE),
(5, 'Hermana Teresa - Pan Compartido', 'receptora@pancompartido.org', '$2a$10$7HCDGsvQ4XcAdcY8cfYH4OvEUBdo/PFqFhG6oR45qWGnKFLPncenK', 'RECEPTORA', 3, TRUE),
(6, 'Trabajadora Social Laura', 'receptora@comedoresperanza.org', '$2a$10$7HCDGsvQ4XcAdcY8cfYH4OvEUBdo/PFqFhG6oR45qWGnKFLPncenK', 'RECEPTORA', 4, TRUE),
(7, 'Delegado Abuelitos de la Paz', 'suspendido@abuelitospaz.org', '$2a$10$7HCDGsvQ4XcAdcY8cfYH4OvEUBdo/PFqFhG6oR45qWGnKFLPncenK', 'RECEPTORA', 5, TRUE)
ON CONFLICT (id_usuario) DO NOTHING;

ALTER SEQUENCE usuario_id_usuario_seq RESTART WITH 8;

-- Lotes disponibles
INSERT INTO lote (
    id_lote, nombre, descripcion, categoria_id, donante_id,
    cantidad_inicial, cantidad_disponible, unidad_minima, multiplo,
    estado, estado_alimento, ubicacion, instrucciones_recogida, contacto,
    fecha_registro, fecha_caducidad
) VALUES
(
    1,
    'Sopa nutritiva y verduras cocidas',
    'Porciones individuales empacadas en recipientes térmicos, aptas para consumo el mismo día.',
    5, 1,
    50.000, 50.000, 10.000, 5.000,
    'DISPONIBLE', 'FRESCO',
    'Centro Histórico, Carrera 7 # 12-40',
    'Ingresar por el muelle de carga posterior. Preguntar por el Chef Martín.',
    'Martín Pérez - 3101234567',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP + INTERVAL '6 hours'
),
(
    2,
    'Lote de pan campesino e integral',
    'Bolsas selladas de 10 unidades de pan recién horneado del día anterior.',
    2, 2,
    100.000, 100.000, 20.000, 10.000,
    'DISPONIBLE', 'FRESCO',
    'Zona Industrial, Calle 26 # 68-15',
    'Reclamar en el área de despachos con documento de identificación.',
    'Bodega Despachos - 3157654321',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP + INTERVAL '24 hours'
),
(
    3,
    'Frutas mixtas (Manzanas y Plátanos)',
    'Canastillas con fruta en punto óptimo de maduración.',
    1, 1,
    40.000, 40.000, 10.000, 5.000,
    'DISPONIBLE', 'FRESCO',
    'Centro Histórico, Carrera 7 # 12-40',
    'Presentarse en recepción principal con recipientes limpios.',
    'Martín Pérez - 3101234567',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP + INTERVAL '3 hours'
)
ON CONFLICT (id_lote) DO NOTHING;

ALTER SEQUENCE lote_id_lote_seq RESTART WITH 4;

-- Strikes demostrativos para la cuenta suspendida
INSERT INTO strike (id_strike, organizacion_id, asignacion_id, nombre_strike, detalles, fecha_registro, vigente) VALUES
(1, 5, NULL, 'INASISTENCIA_RETIRO', 'No se presentó a retirar lote asignado', CURRENT_TIMESTAMP - INTERVAL '5 days', TRUE),
(2, 5, NULL, 'FUERA_DE_FRANJA', 'Llegada 3 horas después de la franja horaria', CURRENT_TIMESTAMP - INTERVAL '3 days', TRUE),
(3, 5, NULL, 'INASISTENCIA_RETIRO', 'Reincidencia en inasistencia', CURRENT_TIMESTAMP - INTERVAL '1 day', TRUE)
ON CONFLICT (id_strike) DO NOTHING;

ALTER SEQUENCE strike_id_strike_seq RESTART WITH 4;

-- Historial inicial de auditoría (RN04)
INSERT INTO historial_estado (entidad, entidad_id, estado_anterior, estado_nuevo, usuario_responsable_id, justificacion) VALUES
('LOTE', 1, 'BORRADOR', 'DISPONIBLE', 3, 'Publicación inicial del lote por parte del donante'),
('LOTE', 2, 'BORRADOR', 'DISPONIBLE', 4, 'Publicación de lote de panadería'),
('LOTE', 3, 'BORRADOR', 'DISPONIBLE', 3, 'Publicación con alerta de rescate urgente'),
('ORGANIZACION', 5, 'ACTIVA', 'BLOQUEADA', 2, 'Suspensión automática tras acumular 3 strikes vigentes');
