-- ============================================================================
-- PROYECTO: AlimentaRed - Plataforma de Rescate y Distribución Responsable de Alimentos
-- MOTOR: PostgreSQL 15+ / Supabase
-- NORMALIZACIÓN: Tercera Forma Normal (3FN)
-- ARQUITECTURA: Relacional, con integridad referencial estricta, restricciones CHECK,
--               triggers de reglas de negocio y vistas optimizadas.
-- ============================================================================

-- Habilitar extensiones necesarias
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Limpieza preventiva de objetos en caso de reejecución
DROP VIEW IF EXISTS v_indicadores_impacto CASCADE;
DROP VIEW IF EXISTS v_lotes_disponibles CASCADE;

DROP TABLE IF EXISTS historial_estado CASCADE;
DROP TABLE IF EXISTS strike CASCADE;
DROP TABLE IF EXISTS incidencia CASCADE;
DROP TABLE IF EXISTS entrega CASCADE;
DROP TABLE IF EXISTS asignacion CASCADE;
DROP TABLE IF EXISTS solicitud CASCADE;
DROP TABLE IF EXISTS lote CASCADE;
DROP TABLE IF EXISTS estado CASCADE;
DROP TABLE IF EXISTS categoria_alimento CASCADE;
DROP TABLE IF EXISTS tipo_alimento CASCADE;
DROP TABLE IF EXISTS usuarios CASCADE;
DROP TABLE IF EXISTS usuario CASCADE;
DROP TABLE IF EXISTS organizacion CASCADE;
DROP TABLE IF EXISTS rol CASCADE;

-- ============================================================================
-- 1. USUARIOS Y ACCESOS (MÓDULO DE SEGURIDAD Y CONTROL DE ENTIDADES)
-- ============================================================================

-- Tabla: rol
-- Define los niveles de acceso del sistema (Donante, Receptora, Coordinador, Administrador).
CREATE TABLE rol (
    id_rol BIGSERIAL PRIMARY KEY,
    nombre VARCHAR(40) NOT NULL UNIQUE,
    descripcion VARCHAR(150),
    CONSTRAINT chk_rol_nombre CHECK (nombre IN ('ROLE_DONANTE', 'ROLE_RECEPTORA', 'ROLE_COORDINADOR', 'ROLE_ADMINISTRADOR'))
);

COMMENT ON TABLE rol IS 'Catálogo de roles estrictos del sistema AlimentaRed';

-- Tabla: organizacion
-- Centraliza a los comercios donantes y fundaciones receptoras, gestionando su estado de verificación (RF02) y penalizaciones.
CREATE TABLE organizacion (
    id_organizacion BIGSERIAL PRIMARY KEY,
    nit VARCHAR(20) NOT NULL UNIQUE,
    nombre VARCHAR(150) NOT NULL,
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('DONANTE', 'RECEPTORA')),
    ubicacion VARCHAR(150) NOT NULL,
    correo VARCHAR(120) NOT NULL UNIQUE,
    telefono VARCHAR(25) NOT NULL,
    estado_cuenta VARCHAR(30) NOT NULL DEFAULT 'pendiente_verificacion',
    verificada BOOLEAN NOT NULL DEFAULT FALSE,
    bloqueada BOOLEAN NOT NULL DEFAULT FALSE,
    strikes_acumulados INTEGER NOT NULL DEFAULT 0 CHECK (strikes_acumulados >= 0),
    strikes_vigentes INTEGER NOT NULL DEFAULT 0 CHECK (strikes_vigentes >= 0),
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT chk_organizacion_estado_cuenta CHECK (
        estado_cuenta IN ('pendiente_verificacion', 'activa', 'suspendida_strikes', 'inactiva')
    )
);

COMMENT ON TABLE organizacion IS 'Comercios donantes y entidades receptoras de alimentos';
CREATE INDEX idx_organizacion_tipo ON organizacion(tipo);
CREATE INDEX idx_organizacion_estado_cuenta ON organizacion(estado_cuenta);

-- Tabla: usuarios
-- Almacena las credenciales y perfiles de los operadores humanos vinculados a roles y organizaciones.
CREATE TABLE usuarios (
    id_usuario BIGSERIAL PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    correo VARCHAR(150) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    id_rol BIGINT NOT NULL REFERENCES rol(id_rol) ON UPDATE CASCADE,
    id_organizacion BIGINT NULL REFERENCES organizacion(id_organizacion) ON DELETE SET NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_correo_valido CHECK (correo ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

COMMENT ON TABLE usuarios IS 'Cuentas de acceso autenticado a la plataforma';
CREATE INDEX idx_usuarios_correo ON usuarios(correo);
CREATE INDEX idx_usuarios_rol ON usuarios(id_rol);

-- ============================================================================
-- 2. CATÁLOGO E INVENTARIO
-- ============================================================================

-- Tabla: categoria_alimento (compatible con tipo_alimento)
-- Tipifica los alimentos e incluye propiedades base.
CREATE TABLE categoria_alimento (
    id_categoria BIGSERIAL PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE,
    descripcion VARCHAR(200),
    tiempo_estimado_vida_util INTERVAL NULL,
    unidad_medida VARCHAR(25) NOT NULL CHECK (unidad_medida IN ('KG', 'LITROS', 'UNIDADES', 'PORCION', 'L'))
);

COMMENT ON TABLE categoria_alimento IS 'Categorización de alimentos rescatables';

-- Tabla: estado
-- Normaliza el ciclo de vida de los lotes y transacciones.
CREATE TABLE estado (
    id_estado BIGSERIAL PRIMARY KEY,
    nombre VARCHAR(35) NOT NULL UNIQUE,
    descripcion VARCHAR(150),
    CONSTRAINT chk_estado_catalogo CHECK (
        nombre IN ('BORRADOR', 'DISPONIBLE', 'ASIGNADO', 'ENTREGADO', 'INCIDENCIA', 'CANCELADO', 'VENCIDO')
    )
);

COMMENT ON TABLE estado IS 'Estados normalizados de ciclo de vida del inventario';

-- Tabla: lote
-- Núcleo de la oferta alimentaria con control de disponibilidad, fraccionamiento, múltiplos y franjas horarias.
CREATE TABLE lote (
    id_lote BIGSERIAL PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    descripcion VARCHAR(500) NOT NULL,
    id_categoria BIGINT NOT NULL REFERENCES categoria_alimento(id_categoria) ON UPDATE CASCADE,
    id_donante BIGINT NOT NULL REFERENCES organizacion(id_organizacion) ON DELETE RESTRICT,
    id_estado BIGINT NOT NULL REFERENCES estado(id_estado) ON UPDATE CASCADE,
    estado_alimento VARCHAR(20) DEFAULT 'FRESCO' CHECK (estado_alimento IN ('FRESCO', 'MEDIO', 'PODRIDO')),
    cantidad_inicial NUMERIC(10,2) NOT NULL CHECK (cantidad_inicial > 0),
    cantidad_disponible NUMERIC(10,2) NOT NULL CHECK (cantidad_disponible >= 0),
    unidad_minima_solicitud NUMERIC(10,2) NOT NULL CHECK (unidad_minima_solicitud > 0),
    multiplo_entrega NUMERIC(10,2) NOT NULL DEFAULT 1.00 CHECK (multiplo_entrega > 0),
    franja_horaria_inicio TIME NOT NULL,
    franja_horaria_fin TIME NOT NULL,
    instrucciones_recogida TEXT NOT NULL,
    contacto VARCHAR(150),
    ubicacion VARCHAR(200),
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_limite_consumo TIMESTAMP NOT NULL,
    version BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT chk_lote_disponibilidad CHECK (cantidad_disponible <= cantidad_inicial),
    CONSTRAINT chk_lote_unidad_minima CHECK (unidad_minima_solicitud <= cantidad_inicial),
    CONSTRAINT chk_lote_franja_horaria CHECK (franja_horaria_inicio < franja_horaria_fin)
);

COMMENT ON TABLE lote IS 'Lotes de alimentos publicados para donación';
CREATE INDEX idx_lote_donante ON lote(id_donante);
CREATE INDEX idx_lote_categoria ON lote(id_categoria);
CREATE INDEX idx_lote_estado ON lote(id_estado);
CREATE INDEX idx_lote_caducidad ON lote(fecha_limite_consumo);

-- ============================================================================
-- 3. MOTOR TRANSACCIONAL LOGÍSTICO (SOLICITUD, ASIGNACIÓN Y ENTREGA)
-- ============================================================================

-- Tabla: solicitud
-- Gestiona la ventana de empate de 60s (RN09), el SLA de 1h (RN06) y la cantidad requerida.
CREATE TABLE solicitud (
    id_solicitud BIGSERIAL PRIMARY KEY,
    id_lote BIGINT NOT NULL REFERENCES lote(id_lote) ON DELETE CASCADE,
    id_organizacion BIGINT NOT NULL REFERENCES organizacion(id_organizacion) ON DELETE RESTRICT,
    cantidad_solicitada NUMERIC(10,2) NOT NULL CHECK (cantidad_solicitada > 0),
    estado VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
    fecha_solicitud TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_fin_ventana_empate TIMESTAMP NOT NULL,
    fecha_expiracion_sla TIMESTAMP NOT NULL,
    fecha_resolucion TIMESTAMP,
    en_empate BOOLEAN NOT NULL DEFAULT FALSE,
    motivo_resolucion VARCHAR(500),
    version BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT chk_solicitud_estado CHECK (
        estado IN ('PENDIENTE', 'APROBADO', 'CANCELADO', 'RECHAZADA', 'EXPIRADA', 'COMPLETADA')
    )
);

COMMENT ON TABLE solicitud IS 'Intenciones de reserva creadas por organizaciones receptoras';
CREATE INDEX idx_solicitud_lote ON solicitud(id_lote);
CREATE INDEX idx_solicitud_organizacion ON solicitud(id_organizacion);
CREATE INDEX idx_solicitud_estado_fecha ON solicitud(estado, fecha_solicitud);
CREATE INDEX idx_solicitud_sla ON solicitud(estado, fecha_expiracion_sla) WHERE estado = 'PENDIENTE';

-- Tabla: asignacion
-- Formaliza la reserva aprobada (contrato), autoriza datos privados y maneja la expiración de retiro.
CREATE TABLE asignacion (
    id_asignacion BIGSERIAL PRIMARY KEY,
    id_solicitud BIGINT NOT NULL UNIQUE REFERENCES solicitud(id_solicitud) ON DELETE CASCADE,
    cantidad_asignada NUMERIC(10,2) NOT NULL CHECK (cantidad_asignada > 0),
    cantidad_retirada NUMERIC(10,2) NOT NULL DEFAULT 0.00 CHECK (cantidad_retirada >= 0),
    estado VARCHAR(25) NOT NULL DEFAULT 'ACTIVA',
    auto_asignada BOOLEAN NOT NULL DEFAULT FALSE,
    resuelta_por_desempate BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_asignacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_limite_retiro TIMESTAMP NOT NULL,
    fecha_cierre TIMESTAMP,
    id_usuario_responsable BIGINT NULL REFERENCES usuarios(id_usuario),
    version BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT chk_asignacion_estado CHECK (
        estado IN ('ACTIVA', 'RETIRO_PARCIAL', 'COMPLETADA', 'NO_RECOGIDA', 'CANCELADA', 'CERRADA_CON_RESTOCK')
    ),
    CONSTRAINT chk_asignacion_retiro_max CHECK (cantidad_retirada <= cantidad_asignada)
);

COMMENT ON TABLE asignacion IS 'Contrato formal de reserva aprobado por donante, coordinador o auto-asignación';
CREATE INDEX idx_asignacion_solicitud ON asignacion(id_solicitud);
CREATE INDEX idx_asignacion_estado ON asignacion(estado);

-- Tabla: entrega
-- Controla la logística física en sitio, retiros parciales (RN11) y cumplimiento de franjas (RN12).
CREATE TABLE entrega (
    id_entrega BIGSERIAL PRIMARY KEY,
    id_asignacion BIGINT NOT NULL UNIQUE REFERENCES asignacion(id_asignacion) ON DELETE CASCADE,
    id_solicitud BIGINT NOT NULL REFERENCES solicitud(id_solicitud),
    cantidad_retirada NUMERIC(10,2) NOT NULL CHECK (cantidad_retirada >= 0),
    cantidad_sobrante_restock NUMERIC(10,2) NOT NULL DEFAULT 0.00 CHECK (cantidad_sobrante_restock >= 0),
    fecha_entrega TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cumplio_franja_horaria BOOLEAN NOT NULL DEFAULT TRUE,
    fuera_de_franja BOOLEAN NOT NULL DEFAULT FALSE,
    estado VARCHAR(20) NOT NULL DEFAULT 'COMPLETA',
    observaciones VARCHAR(500),
    id_usuario_responsable BIGINT NOT NULL REFERENCES usuarios(id_usuario),
    CONSTRAINT chk_entrega_estado CHECK (estado IN ('PARCIAL', 'COMPLETA'))
);

COMMENT ON TABLE entrega IS 'Acta de entrega física en sitio con verificación horaria';
CREATE INDEX idx_entrega_asignacion ON entrega(id_asignacion);

-- ============================================================================
-- 4. AUDITORÍA, ANOMALÍAS Y SANCIONES (INCIDENCIA, STRIKE, HISTORIAL)
-- ============================================================================

-- Tabla: incidencia
-- Maneja cancelaciones, reportes de inocuidad alimentaria y discrepancias de inventario.
CREATE TABLE incidencia (
    id_incidencia BIGSERIAL PRIMARY KEY,
    id_lote BIGINT NOT NULL REFERENCES lote(id_lote) ON DELETE CASCADE,
    id_solicitud BIGINT NULL REFERENCES solicitud(id_solicitud) ON DELETE SET NULL,
    tipo_incidencia VARCHAR(40) NOT NULL,
    detalles TEXT NOT NULL,
    dictamen_coordinador TEXT,
    fecha_reporte TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_usuario_reporta BIGINT NOT NULL REFERENCES usuarios(id_usuario),
    CONSTRAINT chk_tipo_incidencia CHECK (
        tipo_incidencia IN ('DAÑO_ALIMENTO', 'CANCELACION_DONANTE', 'APELACION', 'DISCREPANCIA_CANTIDAD', 'OTRO')
    )
);

COMMENT ON TABLE incidencia IS 'Reportes de riesgo sanitario, inocuidad o cancelaciones de lotes';
CREATE INDEX idx_incidencia_lote ON incidencia(id_lote);

-- Tabla: strike
-- Motor de penalizaciones de AlimentaRed (RN08 / RN12) por incumplimientos logísticos o llegadas tardías.
CREATE TABLE strike (
    id_strike BIGSERIAL PRIMARY KEY,
    id_organizacion BIGINT NOT NULL REFERENCES organizacion(id_organizacion) ON DELETE RESTRICT,
    id_asignacion BIGINT NULL REFERENCES asignacion(id_asignacion) ON DELETE SET NULL,
    nombre_strike VARCHAR(60) NOT NULL,
    detalles VARCHAR(500),
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    vigente BOOLEAN NOT NULL DEFAULT TRUE,
    estado VARCHAR(25) NOT NULL DEFAULT 'vigente',
    justificacion_apelacion VARCHAR(500),
    fecha_apelacion TIMESTAMP,
    id_usuario_evaluador BIGINT NULL REFERENCES usuarios(id_usuario),
    CONSTRAINT chk_strike_estado CHECK (estado IN ('vigente', 'apelado', 'retirado'))
);

COMMENT ON TABLE strike IS 'Historial disciplinario de penalizaciones a organizaciones';
CREATE INDEX idx_strike_organizacion ON strike(id_organizacion);
CREATE INDEX idx_strike_vigente ON strike(id_organizacion, vigente);

-- Tabla: historial_estado
-- Trazabilidad obligatoria (RN04): registra cada cambio de estado, fecha exacta y usuario responsable.
CREATE TABLE historial_estado (
    id_historial BIGSERIAL PRIMARY KEY,
    entidad VARCHAR(20) NOT NULL CHECK (entidad IN ('LOTE', 'SOLICITUD', 'ASIGNACION', 'INCIDENCIA', 'ORGANIZACION', 'STRIKE')),
    entidad_id BIGINT NOT NULL,
    estado_anterior VARCHAR(30),
    estado_nuevo VARCHAR(30) NOT NULL,
    id_usuario_responsable BIGINT NULL REFERENCES usuarios(id_usuario),
    fecha TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    justificacion VARCHAR(500)
);

COMMENT ON TABLE historial_estado IS 'Bitácora inmutable de auditoría transaccional para trazabilidad RUP';
CREATE INDEX idx_historial_entidad ON historial_estado(entidad, entidad_id);

-- ============================================================================
-- 5. VISTAS DE NEGOCIO Y PRIVACIDAD (RF04 / RF09)
-- ============================================================================

-- Vista: v_lotes_disponibles
-- Aplica la regla RF04: Oculta 'instrucciones_recogida' y 'contacto' a nivel público.
-- Muestra únicamente lotes en estado DISPONIBLE y no caducados.
CREATE OR REPLACE VIEW v_lotes_disponibles AS
SELECT 
    l.id_lote,
    l.nombre,
    l.descripcion,
    c.nombre AS categoria,
    c.unidad_medida,
    o.nombre AS donante_nombre,
    l.ubicacion,
    l.cantidad_disponible,
    l.unidad_minima_solicitud,
    l.multiplo_entrega,
    l.franja_horaria_inicio,
    l.franja_horaria_fin,
    l.fecha_limite_consumo,
    CASE 
        WHEN l.fecha_limite_consumo <= (CURRENT_TIMESTAMP + INTERVAL '4 hours') THEN TRUE 
        ELSE FALSE 
    END AS rescate_urgente
FROM lote l
JOIN categoria_alimento c ON l.id_categoria = c.id_categoria
JOIN organizacion o ON l.id_donante = o.id_organizacion
JOIN estado e ON l.id_estado = e.id_estado
WHERE e.nombre = 'DISPONIBLE'
  AND l.cantidad_disponible > 0
  AND l.fecha_limite_consumo > CURRENT_TIMESTAMP;

-- Vista: v_indicadores_impacto
-- Consolida estadísticas globales para el Coordinador (RF09).
CREATE OR REPLACE VIEW v_indicadores_impacto AS
SELECT
    COALESCE(SUM(e.cantidad_retirada), 0) AS total_alimentos_recuperados,
    COUNT(DISTINCT e.id_entrega) AS total_entregas_completadas,
    COUNT(DISTINCT l.id_lote) AS total_lotes_publicados,
    COUNT(DISTINCT CASE WHEN o.tipo = 'DONANTE' AND o.estado_cuenta = 'activa' THEN o.id_organizacion END) AS comercios_activos,
    COUNT(DISTINCT CASE WHEN o.tipo = 'RECEPTORA' AND o.estado_cuenta = 'activa' THEN o.id_organizacion END) AS fundaciones_activas,
    COUNT(DISTINCT CASE WHEN s.vigente = TRUE THEN s.id_strike END) AS strikes_vigentes_totales
FROM organizacion o
LEFT JOIN lote l ON l.id_donante = o.id_organizacion
LEFT JOIN solicitud sol ON sol.id_lote = l.id_lote
LEFT JOIN asignacion a ON a.id_solicitud = sol.id_solicitud
LEFT JOIN entrega e ON e.id_asignacion = a.id_asignacion
LEFT JOIN strike s ON s.id_organizacion = o.id_organizacion;

-- ============================================================================
-- 6. TRIGGERS Y FUNCIONES DE INTEGRIDAD TRANSACCIONAL
-- ============================================================================

-- Función y Trigger: Sanciones disciplinarias y bloqueo automático (RN08 / RN12)
CREATE OR REPLACE FUNCTION fn_actualizar_strikes_organizacion()
RETURNS TRIGGER AS $$
DECLARE
    v_conteo_vigentes INTEGER;
    v_id_org BIGINT;
BEGIN
    v_id_org := COALESCE(NEW.id_organizacion, OLD.id_organizacion);
    
    -- Contar strikes vigentes de la organización
    SELECT COUNT(*) INTO v_conteo_vigentes
    FROM strike
    WHERE id_organizacion = v_id_org AND vigente = TRUE;

    -- Actualizar la tabla organizacion
    UPDATE organizacion
    SET strikes_vigentes = v_conteo_vigentes,
        strikes_acumulados = (SELECT COUNT(*) FROM strike WHERE id_organizacion = v_id_org),
        bloqueada = (v_conteo_vigentes >= 3),
        estado_cuenta = CASE 
            WHEN v_conteo_vigentes >= 3 THEN 'suspendida_strikes'
            WHEN verificada = TRUE THEN 'activa'
            ELSE 'pendiente_verificacion'
        END
    WHERE id_organizacion = v_id_org;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_actualizar_strikes ON strike;
CREATE TRIGGER trg_actualizar_strikes
AFTER INSERT OR UPDATE OR DELETE ON strike
FOR EACH ROW
EXECUTE FUNCTION fn_actualizar_strikes_organizacion();

-- Función y Trigger: Validación previa de creación de solicitud (RN01, RN07, RN10)
CREATE OR REPLACE FUNCTION fn_validar_creacion_solicitud()
RETURNS TRIGGER AS $$
DECLARE
    v_lote RECORD;
    v_org RECORD;
    v_solicitudes_activas INTEGER;
    v_remanente NUMERIC(10,2);
BEGIN
    -- 1. Validar estado de la organización
    SELECT * INTO v_org FROM organizacion WHERE id_organizacion = NEW.id_organizacion;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Organización no encontrada: %', NEW.id_organizacion;
    END IF;

    IF v_org.bloqueada = TRUE OR v_org.estado_cuenta = 'suspendida_strikes' THEN
        RAISE EXCEPTION 'La organización se encuentra suspendida por acumulación de strikes';
    END IF;

    -- 2. Validar límite de 3 solicitudes activas simultáneas (RN07)
    SELECT COUNT(*) INTO v_solicitudes_activas
    FROM solicitud
    WHERE id_organizacion = NEW.id_organizacion
      AND estado IN ('PENDIENTE', 'APROBADO');

    IF v_solicitudes_activas >= 3 THEN
        RAISE EXCEPTION 'RN07: Límite equitativo alcanzado. La organización receptora ya tiene 3 solicitudes activas';
    END IF;

    -- 3. Validar estado y caducidad del lote (RN01)
    SELECT l.*, e.nombre AS estado_nombre 
    INTO v_lote 
    FROM lote l
    JOIN estado e ON l.id_estado = e.id_estado
    WHERE l.id_lote = NEW.id_lote;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lote no encontrado: %', NEW.id_lote;
    END IF;

    IF v_lote.estado_nombre <> 'DISPONIBLE' THEN
        RAISE EXCEPTION 'RN01: El lote no se encuentra disponible (Estado: %)', v_lote.estado_nombre;
    END IF;

    IF v_lote.fecha_limite_consumo <= CURRENT_TIMESTAMP THEN
        RAISE EXCEPTION 'RN01: El lote se encuentra vencido desde %', v_lote.fecha_limite_consumo;
    END IF;

    -- 4. Validar integridad de inventario y fraccionamiento (RN02, RN05, RN10)
    IF NEW.cantidad_solicitada > v_lote.cantidad_disponible THEN
        RAISE EXCEPTION 'RN02: La cantidad solicitada (%) excede la cantidad disponible (%)', 
            NEW.cantidad_solicitada, v_lote.cantidad_disponible;
    END IF;

    IF NEW.cantidad_solicitada < v_lote.unidad_minima_solicitud THEN
        RAISE EXCEPTION 'RN05: La cantidad solicitada (%) es menor a la unidad mínima permitida (%)', 
            NEW.cantidad_solicitada, v_lote.unidad_minima_solicitud;
    END IF;

    -- Validación de múltiplo (RN10)
    IF MOD(NEW.cantidad_solicitada, v_lote.multiplo_entrega) <> 0 THEN
        RAISE EXCEPTION 'RN10: La cantidad solicitada (%) debe ser múltiplo de %', 
            NEW.cantidad_solicitada, v_lote.multiplo_entrega;
    END IF;

    -- Validación de remanente útil (RN10)
    v_remanente := v_lote.cantidad_disponible - NEW.cantidad_solicitada;
    IF v_remanente > 0 AND v_remanente < v_lote.unidad_minima_solicitud THEN
        RAISE EXCEPTION 'RN10: La solicitud deja un remanente inútil de %. El saldo restante debe ser 0 o >= %', 
            v_remanente, v_lote.unidad_minima_solicitud;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validar_solicitud ON solicitud;
CREATE TRIGGER trg_validar_solicitud
BEFORE INSERT ON solicitud
FOR EACH ROW
EXECUTE FUNCTION fn_validar_creacion_solicitud();

-- ============================================================================
-- 7. DATOS INICIALES (SEED DATA)
-- ============================================================================

-- Inserción de Roles
INSERT INTO rol (id_rol, nombre, descripcion) VALUES
(1, 'ROLE_ADMINISTRADOR', 'Administrador técnico global de la plataforma'),
(2, 'ROLE_COORDINADOR', 'Coordinador de red comunitaria y supervisor logístico'),
(3, 'ROLE_DONANTE', 'Comercio o restaurante donante de alimentos'),
(4, 'ROLE_RECEPTORA', 'Fundación, comedor comunitario u ONG receptora')
ON CONFLICT (id_rol) DO UPDATE SET nombre = EXCLUDED.nombre;

ALTER SEQUENCE rol_id_rol_seq RESTART WITH 5;

-- Inserción de Estados de Lote / Transacción
INSERT INTO estado (id_estado, nombre, descripcion) VALUES
(1, 'BORRADOR', 'Lote guardado pendiente de confirmación o verificación'),
(2, 'DISPONIBLE', 'Lote activo visible en el catálogo para solicitudes'),
(3, 'ASIGNADO', 'Lote con reserva aprobada y asignado a una organización'),
(4, 'ENTREGADO', 'Lote retirado y entrega logística física cerrada'),
(5, 'INCIDENCIA', 'Lote pausado por queja de inocuidad o reporte operativo'),
(6, 'CANCELADO', 'Lote cancelado por el donante o coordinador'),
(7, 'VENCIDO', 'Lote expirado sin retiro antes de la fecha límite')
ON CONFLICT (id_estado) DO UPDATE SET nombre = EXCLUDED.nombre;

ALTER SEQUENCE estado_id_estado_seq RESTART WITH 8;

-- Inserción de Categorías de Alimento
INSERT INTO categoria_alimento (id_categoria, nombre, descripcion, unidad_medida) VALUES
(1, 'Frutas y verduras', 'Productos frescos de origen vegetal', 'KG'),
(2, 'Panadería', 'Pan, pasteles y productos horneados', 'UNIDADES'),
(3, 'Lácteos', 'Leche, yogures, quesos y derivados lácteos', 'LITROS'),
(4, 'Proteínas', 'Carnes, pollo, pescado y huevos', 'KG'),
(5, 'Comidas preparadas', 'Platos listos empacados para consumo inmediato', 'PORCION'),
(6, 'Granos y abarrotes', 'Arroz, frijol, enlatados y no perecederos', 'KG')
ON CONFLICT (id_categoria) DO UPDATE SET nombre = EXCLUDED.nombre;

ALTER SEQUENCE categoria_alimento_id_categoria_seq RESTART WITH 7;

-- Inserción de Organizaciones de Prueba
INSERT INTO organizacion (id_organizacion, nit, nombre, tipo, ubicacion, correo, telefono, estado_cuenta, verificada, bloqueada, strikes_acumulados, strikes_vigentes) VALUES
(1, '901234567-1', 'Restaurante Sabor Casero', 'DONANTE', 'Centro Histórico, Carrera 7 # 12-40', 'contacto@saborcasero.com', '3101234567', 'activa', TRUE, FALSE, 0, 0),
(2, '901876543-2', 'Panificadora Central SAS', 'DONANTE', 'Zona Industrial, Calle 26 # 68-15', 'donaciones@panificadoracentral.com', '3157654321', 'activa', TRUE, FALSE, 0, 0),
(3, '800987654-3', 'Fundación Pan Compartido', 'RECEPTORA', 'Comuna 4, Manzana 12 Casa 5', 'direccion@pancompartido.org', '3209876543', 'activa', TRUE, FALSE, 0, 0),
(4, '800345678-4', 'Comedor Infantil Esperanza', 'RECEPTORA', 'Barrio El Carmen, Transversal 15 # 3-22', 'coordinacion@comedoresperanza.org', '3183456789', 'activa', TRUE, FALSE, 0, 0),
(5, '800555999-5', 'Hogar Abuelitos de la Paz', 'RECEPTORA', 'Barrio San Carlos, Carrera 10 # 45-10', 'contacto@abuelitospaz.org', '3115559999', 'suspendida_strikes', TRUE, TRUE, 3, 3)
ON CONFLICT (id_organizacion) DO NOTHING;

ALTER SEQUENCE organizacion_id_organizacion_seq RESTART WITH 6;

-- Inserción de Usuarios de Prueba
-- Contraseña para Admin12345: $2a$10$wE2o1bC2y022oHkFp/V02.0Jvh1r4hXhE4lq4Yn2H9uP/0c9zR2nK
-- Contraseña para Coord12345: $2a$10$tZ2E7/i/f8uVnQ9iQ2tTte2yG1Fj1uGkE5o7K7o9aK.t0y4rM7hVq
-- Contraseña para Pass12345:  $2a$10$N.zmdr9k7uOCQb376NoUnuTJ8iAt6Z5EHsM8lE9lBOsl7iKTVKIUi
INSERT INTO usuarios (id_usuario, nombre, correo, password_hash, id_rol, id_organizacion, activo) VALUES
(1, 'Administrador AlimentaRed', 'admin@alimentared.com', '$2a$10$wE2o1bC2y022oHkFp/V02.0Jvh1r4hXhE4lq4Yn2H9uP/0c9zR2nK', 1, NULL, TRUE),
(2, 'Coordinador Red Comunitaria', 'coordinador@alimentared.com', '$2a$10$tZ2E7/i/f8uVnQ9iQ2tTte2yG1Fj1uGkE5o7K7o9aK.t0y4rM7hVq', 2, NULL, TRUE),
(3, 'Chef Martín Pérez', 'donante@saborcasero.com', '$2a$10$N.zmdr9k7uOCQb376NoUnuTJ8iAt6Z5EHsM8lE9lBOsl7iKTVKIUi', 3, 1, TRUE),
(4, 'Gerente Panificadora Central', 'donante@panificadoracentral.com', '$2a$10$N.zmdr9k7uOCQb376NoUnuTJ8iAt6Z5EHsM8lE9lBOsl7iKTVKIUi', 3, 2, TRUE),
(5, 'Hermana Teresa - Pan Compartido', 'receptora@pancompartido.org', '$2a$10$N.zmdr9k7uOCQb376NoUnuTJ8iAt6Z5EHsM8lE9lBOsl7iKTVKIUi', 4, 3, TRUE),
(6, 'Trabajadora Social Laura', 'receptora@comedoresperanza.org', '$2a$10$N.zmdr9k7uOCQb376NoUnuTJ8iAt6Z5EHsM8lE9lBOsl7iKTVKIUi', 4, 4, TRUE),
(7, 'Delegado Abuelitos de la Paz', 'suspendido@abuelitospaz.org', '$2a$10$N.zmdr9k7uOCQb376NoUnuTJ8iAt6Z5EHsM8lE9lBOsl7iKTVKIUi', 4, 5, TRUE)
ON CONFLICT (id_usuario) DO NOTHING;

ALTER SEQUENCE usuarios_id_usuario_seq RESTART WITH 8;

-- Inserción de Lotes de Prueba
INSERT INTO lote (
    id_lote, nombre, descripcion, id_categoria, id_donante, id_estado, estado_alimento,
    cantidad_inicial, cantidad_disponible, unidad_minima_solicitud, multiplo_entrega,
    franja_horaria_inicio, franja_horaria_fin, instrucciones_recogida, contacto, ubicacion,
    fecha_registro, fecha_limite_consumo
) VALUES
(
    1,
    'Sopa nutritiva y verduras cocidas',
    'Porciones individuales empacadas en recipientes térmicos, aptas para consumo el mismo día.',
    5, 1, 2, 'FRESCO',
    50.00, 50.00, 10.00, 5.00,
    '15:00:00', '18:00:00',
    'Ingresar por el muelle de carga posterior. Preguntar por el Chef Martín.',
    'Martín Pérez - 3101234567',
    'Centro Histórico, Carrera 7 # 12-40',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP + INTERVAL '6 hours'
),
(
    2,
    'Lote de pan campesino e integral',
    'Bolsas selladas de 10 unidades de pan recién horneado del día anterior.',
    2, 2, 2, 'FRESCO',
    100.00, 100.00, 20.00, 10.00,
    '08:00:00', '11:00:00',
    'Reclamar en el área de despachos con documento de identificación institucional.',
    'Bodega Despachos - 3157654321',
    'Zona Industrial, Calle 26 # 68-15',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP + INTERVAL '24 hours'
),
(
    3,
    'Frutas mixtas (Manzanas y Plátanos)',
    'Canastillas con fruta en punto óptimo de maduración.',
    1, 1, 2, 'FRESCO',
    40.00, 40.00, 10.00, 5.00,
    '16:00:00', '19:00:00',
    'Presentarse en recepción principal con recipientes limpios.',
    'Martín Pérez - 3101234567',
    'Centro Histórico, Carrera 7 # 12-40',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP + INTERVAL '3 hours' -- Dispara alerta de rescate urgente (< 4h)
)
ON CONFLICT (id_lote) DO NOTHING;

ALTER SEQUENCE lote_id_lote_seq RESTART WITH 4;

-- Inserción de Solicitud y Asignación de Ejemplo (Ciclo demostrativo)
INSERT INTO solicitud (
    id_solicitud, id_lote, id_organizacion, cantidad_solicitada, estado,
    fecha_solicitud, fecha_fin_ventana_empate, fecha_expiracion_sla
) VALUES
(
    1, 2, 3, 30.00, 'APROBADO',
    CURRENT_TIMESTAMP - INTERVAL '30 minutes',
    CURRENT_TIMESTAMP - INTERVAL '29 minutes',
    CURRENT_TIMESTAMP + INTERVAL '30 minutes'
)
ON CONFLICT (id_solicitud) DO NOTHING;

ALTER SEQUENCE solicitud_id_solicitud_seq RESTART WITH 2;

INSERT INTO asignacion (
    id_asignacion, id_solicitud, cantidad_asignada, cantidad_retirada,
    estado, auto_asignada, resuelta_por_desempate, fecha_asignacion,
    fecha_limite_retiro, id_usuario_responsable
) VALUES
(
    1, 1, 30.00, 0.00,
    'ACTIVA', FALSE, FALSE,
    CURRENT_TIMESTAMP - INTERVAL '20 minutes',
    CURRENT_TIMESTAMP + INTERVAL '12 hours',
    4 -- Gerente de Panificadora
)
ON CONFLICT (id_asignacion) DO NOTHING;

ALTER SEQUENCE asignacion_id_asignacion_seq RESTART WITH 2;

-- Actualizar disponibilidad del lote 2 debido a la asignación de 30 unidades
UPDATE lote SET cantidad_disponible = cantidad_disponible - 30.00 WHERE id_lote = 2;

-- Registro de Strike demostrativo para la organización suspendida (3 strikes)
INSERT INTO strike (id_strike, id_organizacion, id_asignacion, nombre_strike, detalles, fecha_registro, vigente, estado) VALUES
(1, 5, NULL, 'INASISTENCIA_RETIRO', 'No se presentó a retirar el lote asignado en la franja horaria programada', CURRENT_TIMESTAMP - INTERVAL '10 days', TRUE, 'vigente'),
(2, 5, NULL, 'FUERA_DE_FRANJA', 'Retiro realizado con 3 horas de retraso sin justificación previa', CURRENT_TIMESTAMP - INTERVAL '5 days', TRUE, 'vigente'),
(3, 5, NULL, 'INASISTENCIA_RETIRO', 'Inasistencia no informada comprometiendo la inocuidad del alimento', CURRENT_TIMESTAMP - INTERVAL '1 day', TRUE, 'vigente')
ON CONFLICT (id_strike) DO NOTHING;

ALTER SEQUENCE strike_id_strike_seq RESTART WITH 4;

-- Bitácora inicial de auditoría (RN04)
INSERT INTO historial_estado (entidad, entidad_id, estado_anterior, estado_nuevo, id_usuario_responsable, justificacion) VALUES
('LOTE', 1, 'BORRADOR', 'DISPONIBLE', 3, 'Publicación inicial del lote por parte del donante'),
('LOTE', 2, 'BORRADOR', 'DISPONIBLE', 4, 'Publicación de lote de panadería'),
('LOTE', 3, 'BORRADOR', 'DISPONIBLE', 3, 'Publicación con alerta de rescate urgente'),
('SOLICITUD', 1, 'PENDIENTE', 'APROBADO', 4, 'Aprobación de solicitud dentro del SLA'),
('ORGANIZACION', 5, 'activa', 'suspendida_strikes', 2, 'Suspensión automática tras acumular 3 strikes vigentes');
