-- =====================================================================
--  AutoRim · Base de datos COMPLETA (MySQL 8 / MariaDB 10.5+)
--  UN SOLO ARCHIVO: estructura + reglas CHECK + pagos + triggers de
--  auditoría + vistas + datos de ejemplo + administrador inicial.
--  12 tablas, todas con prefijo MB_DG_:
--    10 de negocio (USUARIOS, AUTOS, COLORES, ACABADOS, RINES, LLANTAS,
--    MEDIDAS, CONFIGURACIONES, PEDIDOS, PEDIDO_ITEMS) + PAGOS + AUDITORIA.
--  El administrador NO tiene tabla propia: es una fila de MB_DG_USUARIOS
--  con rol = 'admin' y su codigo_acceso_hash.
--
--  Uso:  phpMyAdmin → Importar (sin seleccionar base)  o
--        mysql -u root -p < autorim_completo.sql
--
--  ¡OJO! Este script BORRA y vuelve a crear la base "autorim".
--  Úsalo para una instalación limpia.
-- =====================================================================

DROP DATABASE IF EXISTS autorim;
CREATE DATABASE autorim CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE autorim;

-- ---------------------------------------------------------------------
--  1. USUARIOS (clientes y administradores)
--  Contraseña y código de acceso se guardan con hash bcrypt, nunca en claro.
-- ---------------------------------------------------------------------
CREATE TABLE MB_DG_USUARIOS (
  id                  INT AUTO_INCREMENT NOT NULL,
  email               VARCHAR(190) NOT NULL,
  password_hash       VARCHAR(255) NOT NULL,
  rol                 ENUM('cliente','admin') NOT NULL DEFAULT 'cliente',
  codigo_acceso_hash  VARCHAR(255) NULL,          -- solo administradores (panel /admin)
  creado_en           TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_usuarios_email (email),
  CONSTRAINT ck_usuarios_admin CHECK (rol <> 'admin' OR codigo_acceso_hash IS NOT NULL)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  2-7. CATÁLOGO
-- ---------------------------------------------------------------------
CREATE TABLE MB_DG_AUTOS (
  id          INT AUTO_INCREMENT NOT NULL,
  marca       VARCHAR(60)  NOT NULL,
  nombre      VARCHAR(100) NOT NULL,
  carroceria  ENUM('gt','coupe','muscle','suv') NOT NULL,
  color_base  CHAR(7)      NOT NULL,
  activo      BOOLEAN      NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id),
  UNIQUE KEY uq_autos_nombre (nombre),
  KEY ix_autos_marca (marca),
  CONSTRAINT ck_autos_color CHECK (color_base REGEXP '^#[0-9a-fA-F]{6}$')
) ENGINE=InnoDB;

CREATE TABLE MB_DG_COLORES (
  id      INT AUTO_INCREMENT NOT NULL,
  nombre  VARCHAR(40) NOT NULL,
  hex     CHAR(7)     NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_colores_nombre (nombre),
  UNIQUE KEY uq_colores_hex (hex),
  CONSTRAINT ck_colores_hex CHECK (hex REGEXP '^#[0-9a-fA-F]{6}$')
) ENGINE=InnoDB;

CREATE TABLE MB_DG_ACABADOS (
  id      INT AUTO_INCREMENT NOT NULL,
  nombre  VARCHAR(40) NOT NULL,
  hex     CHAR(7)     NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_acabados_nombre (nombre),
  UNIQUE KEY uq_acabados_hex (hex),
  CONSTRAINT ck_acabados_hex CHECK (hex REGEXP '^#[0-9a-fA-F]{6}$')
) ENGINE=InnoDB;

CREATE TABLE MB_DG_RINES (
  id            INT AUTO_INCREMENT NOT NULL,
  nombre        VARCHAR(60)  NOT NULL,
  estilo        ENUM('five','mesh','turbine','multi') NOT NULL,
  acabado_base  CHAR(7)      NOT NULL,
  precio        INT NOT NULL,                      -- COP, set de 4
  activo        BOOLEAN      NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id),
  UNIQUE KEY uq_rines_nombre (nombre),
  CONSTRAINT ck_rines_precio CHECK (precio >= 0),
  CONSTRAINT ck_rines_acabado CHECK (acabado_base REGEXP '^#[0-9a-fA-F]{6}$')
) ENGINE=InnoDB;

CREATE TABLE MB_DG_LLANTAS (
  id             INT AUTO_INCREMENT NOT NULL,
  codigo         VARCHAR(10)  NOT NULL,            -- 'sport', 'off', 'pre' (se usa en la URL)
  nombre         VARCHAR(60)  NOT NULL,
  svg_radio      INT NOT NULL,                     -- radio del dibujo SVG
  svg_radio_rin  INT NOT NULL,                     -- radio del rin dentro de la llanta
  precio         INT NOT NULL,                     -- COP, set de 4
  activo         BOOLEAN      NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id),
  UNIQUE KEY uq_llantas_codigo (codigo),
  CONSTRAINT ck_llantas_precio CHECK (precio >= 0),
  CONSTRAINT ck_llantas_radios CHECK (svg_radio >= 1 AND svg_radio_rin >= 1)
) ENGINE=InnoDB;

CREATE TABLE MB_DG_MEDIDAS (                       -- tamaños de rin (17") y de llanta (225/45 R17)
  id        INT AUTO_INCREMENT NOT NULL,
  tipo      ENUM('rin','llanta') NOT NULL,
  etiqueta  VARCHAR(20)  NOT NULL,
  factor    DECIMAL(4,2) NOT NULL,                 -- multiplica el precio base
  PRIMARY KEY (id),
  UNIQUE KEY uq_medidas (tipo, etiqueta),
  CONSTRAINT ck_medidas_factor CHECK (factor > 0)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  8. CONFIGURACIONES: producto armado por el cliente (inmutable).
--     kit = auto+color+rin+llanta · rines = set de 4 · llantas = set de 4
-- ---------------------------------------------------------------------
CREATE TABLE MB_DG_CONFIGURACIONES (
  id                INT AUTO_INCREMENT NOT NULL,
  tipo              ENUM('kit','rines','llantas') NOT NULL,
  nombre            VARCHAR(120)  NOT NULL,
  detalle           VARCHAR(255)  NOT NULL,
  precio_unitario   INT NOT NULL,
  auto_id           INT NULL,
  color_id          INT NULL,
  rin_id            INT NULL,
  acabado_id        INT NULL,                      -- NULL = acabado original
  medida_rin_id     INT NULL,
  ancho_rin         ENUM('7.5J','8.5J','9.5J') NULL,
  llanta_id         INT NULL,
  medida_llanta_id  INT NULL,
  creado_en         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT ck_cfg_precio CHECK (precio_unitario >= 0),
  CONSTRAINT fk_cfg_auto    FOREIGN KEY (auto_id)          REFERENCES MB_DG_AUTOS (id),
  CONSTRAINT fk_cfg_color   FOREIGN KEY (color_id)         REFERENCES MB_DG_COLORES (id),
  CONSTRAINT fk_cfg_rin     FOREIGN KEY (rin_id)           REFERENCES MB_DG_RINES (id),
  CONSTRAINT fk_cfg_acabado FOREIGN KEY (acabado_id)       REFERENCES MB_DG_ACABADOS (id),
  CONSTRAINT fk_cfg_medrin  FOREIGN KEY (medida_rin_id)    REFERENCES MB_DG_MEDIDAS (id),
  CONSTRAINT fk_cfg_llanta  FOREIGN KEY (llanta_id)        REFERENCES MB_DG_LLANTAS (id),
  CONSTRAINT fk_cfg_medlla  FOREIGN KEY (medida_llanta_id) REFERENCES MB_DG_MEDIDAS (id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  9-10. PEDIDOS y sus renglones
-- ---------------------------------------------------------------------
CREATE TABLE MB_DG_PEDIDOS (
  id               INT AUTO_INCREMENT NOT NULL,
  codigo           VARCHAR(20)   NOT NULL,         -- 'AR-123456'
  usuario_id       INT NOT NULL,
  nombre_completo  VARCHAR(120)  NOT NULL,
  direccion        VARCHAR(200)  NOT NULL,
  ciudad           VARCHAR(80)   NOT NULL,
  departamento     VARCHAR(80)   NOT NULL,
  telefono         VARCHAR(30)   NOT NULL,
  subtotal         INT NOT NULL,
  costo_envio      INT NOT NULL DEFAULT 25000,
  total            INT NOT NULL,
  estado           ENUM('pendiente','pagado','enviado','entregado','cancelado') NOT NULL DEFAULT 'pendiente',
  creado_en        TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_pedidos_codigo (codigo),
  KEY ix_pedidos_usuario (usuario_id),
  KEY ix_pedidos_fecha (creado_en),
  CONSTRAINT ck_pedidos_montos CHECK (subtotal >= 0 AND costo_envio >= 0 AND total = subtotal + costo_envio),
  CONSTRAINT fk_pedidos_usuario FOREIGN KEY (usuario_id) REFERENCES MB_DG_USUARIOS (id)
) ENGINE=InnoDB;

CREATE TABLE MB_DG_PEDIDO_ITEMS (
  id                INT AUTO_INCREMENT NOT NULL,
  pedido_id         INT NOT NULL,
  configuracion_id  INT NOT NULL,
  cantidad          INT NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT ck_items_cantidad CHECK (cantidad >= 1),
  CONSTRAINT fk_pi_pedido FOREIGN KEY (pedido_id)        REFERENCES MB_DG_PEDIDOS (id) ON DELETE CASCADE,
  CONSTRAINT fk_pi_config FOREIGN KEY (configuracion_id) REFERENCES MB_DG_CONFIGURACIONES (id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  11. PAGOS (simulados). Solo marca y últimos 4 dígitos; nunca el número
--  completo ni el CVV. Sin ON DELETE CASCADE a propósito: un pedido con
--  pagos no se puede borrar.
-- ---------------------------------------------------------------------
CREATE TABLE MB_DG_PAGOS (
  id                  INT AUTO_INCREMENT NOT NULL,
  pedido_id           INT NOT NULL,
  pasarela            VARCHAR(30) NOT NULL,        -- 'simulada', 'wompi', 'payu'...
  referencia_externa  VARCHAR(80) NULL,
  estado              ENUM('pendiente','aprobado','rechazado','reembolsado') NOT NULL DEFAULT 'pendiente',
  monto               INT NOT NULL,                -- COP, sin decimales
  moneda              CHAR(3) NOT NULL DEFAULT 'COP',
  metodo_tipo         ENUM('tarjeta','pse','nequi') NOT NULL DEFAULT 'tarjeta',
  marca               VARCHAR(20) NULL,
  ultimos4            CHAR(4) NULL,
  creado_en           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  actualizado_en      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_pagos_referencia (referencia_externa),
  KEY ix_pagos_pedido (pedido_id),
  KEY ix_pagos_fecha (creado_en),
  CONSTRAINT fk_pagos_pedido FOREIGN KEY (pedido_id) REFERENCES MB_DG_PEDIDOS (id),
  CONSTRAINT ck_pagos_monto CHECK (monto >= 0),
  CONSTRAINT ck_pagos_ultimos4 CHECK (ultimos4 IS NULL OR ultimos4 REGEXP '^[0-9]{4}$')
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  12. AUDITORÍA: una fila por cada INSERT, UPDATE o DELETE (la llenan los
--  triggers; la app no escribe aquí). Es de solo agregar. usuario_app no es
--  llave foránea a propósito: el historial sobrevive si se borra el usuario.
-- ---------------------------------------------------------------------
CREATE TABLE MB_DG_AUDITORIA (
  id                INT AUTO_INCREMENT NOT NULL,
  tabla             VARCHAR(40)  NOT NULL,
  operacion         ENUM('INSERT','UPDATE','DELETE') NOT NULL,
  registro_id       INT NOT NULL,
  usuario_app       INT NULL,                      -- @app_usuario_id que informa el backend
  usuario_bd        VARCHAR(128) NOT NULL,         -- USER() de MySQL
  fecha             TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  datos_anteriores  JSON NULL,
  datos_nuevos      JSON NULL,
  PRIMARY KEY (id),
  KEY ix_aud_tabla_registro (tabla, registro_id),
  KEY ix_aud_fecha (fecha),
  KEY ix_aud_usuario_app (usuario_app)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  VISTAS del panel de administración
-- ---------------------------------------------------------------------
CREATE VIEW MB_DG_V_PEDIDOS_ADMIN AS
SELECT p.codigo               AS pedido,
       p.creado_en            AS fecha,
       u.email                AS cliente,
       GROUP_CONCAT(CONCAT(c.nombre, ' x', pi.cantidad) ORDER BY pi.id SEPARATOR ', ') AS productos,
       p.total,
       p.estado
FROM MB_DG_PEDIDOS p
JOIN MB_DG_USUARIOS u        ON u.id = p.usuario_id
JOIN MB_DG_PEDIDO_ITEMS pi   ON pi.pedido_id = p.id
JOIN MB_DG_CONFIGURACIONES c ON c.id = pi.configuracion_id
GROUP BY p.id, p.codigo, p.creado_en, u.email, p.total, p.estado;

CREATE VIEW MB_DG_V_RESUMEN_ADMIN AS
SELECT (SELECT COUNT(*) FROM MB_DG_PEDIDOS)                        AS pedidos,
       (SELECT COUNT(*) FROM MB_DG_USUARIOS WHERE rol = 'cliente') AS clientes;

-- ---------------------------------------------------------------------
--  TRIGGERS DE AUDITORÍA (3 por tabla: _INS, _UPD, _DEL)
-- ---------------------------------------------------------------------
DELIMITER $$

-- La auditoría no se puede alterar ni borrar
CREATE TRIGGER MB_DG_TRG_AUDITORIA_UPD BEFORE UPDATE ON MB_DG_AUDITORIA FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'MB_DG_AUDITORIA es de solo lectura: no se permite UPDATE';
END$$
CREATE TRIGGER MB_DG_TRG_AUDITORIA_DEL BEFORE DELETE ON MB_DG_AUDITORIA FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'MB_DG_AUDITORIA es de solo lectura: no se permite DELETE';
END$$

-- MB_DG_USUARIOS (los hashes nunca se guardan en la auditoría)
CREATE TRIGGER MB_DG_TRG_USUARIOS_INS AFTER INSERT ON MB_DG_USUARIOS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_USUARIOS', 'INSERT', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), NULL,
          JSON_OBJECT('id', NEW.id, 'email', NEW.email, 'password_hash', '[oculto]', 'rol', NEW.rol, 'codigo_acceso_hash', '[oculto]', 'creado_en', NEW.creado_en));
END$$
CREATE TRIGGER MB_DG_TRG_USUARIOS_UPD AFTER UPDATE ON MB_DG_USUARIOS FOR EACH ROW
BEGIN
  DECLARE v_antes LONGTEXT;
  DECLARE v_despues LONGTEXT;
  SET v_antes   = JSON_OBJECT('id', OLD.id, 'email', OLD.email, 'password_hash', '[oculto]', 'rol', OLD.rol, 'codigo_acceso_hash', '[oculto]', 'creado_en', OLD.creado_en);
  SET v_despues = JSON_OBJECT('id', NEW.id, 'email', NEW.email, 'password_hash', IF(NEW.password_hash <=> OLD.password_hash, '[oculto]', '[oculto: modificado]'), 'rol', NEW.rol, 'codigo_acceso_hash', IF(NEW.codigo_acceso_hash <=> OLD.codigo_acceso_hash, '[oculto]', '[oculto: modificado]'), 'creado_en', NEW.creado_en);
  IF NOT (v_antes <=> v_despues) THEN
    INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
    VALUES ('MB_DG_USUARIOS', 'UPDATE', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), v_antes, v_despues);
  END IF;
END$$
CREATE TRIGGER MB_DG_TRG_USUARIOS_DEL AFTER DELETE ON MB_DG_USUARIOS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_USUARIOS', 'DELETE', OLD.id, CAST(@app_usuario_id AS UNSIGNED), USER(),
          JSON_OBJECT('id', OLD.id, 'email', OLD.email, 'password_hash', '[oculto]', 'rol', OLD.rol, 'codigo_acceso_hash', '[oculto]', 'creado_en', OLD.creado_en), NULL);
END$$

-- MB_DG_AUTOS
CREATE TRIGGER MB_DG_TRG_AUTOS_INS AFTER INSERT ON MB_DG_AUTOS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_AUTOS', 'INSERT', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), NULL, JSON_OBJECT('id', NEW.id, 'marca', NEW.marca, 'nombre', NEW.nombre, 'carroceria', NEW.carroceria, 'color_base', NEW.color_base, 'activo', NEW.activo));
END$$
CREATE TRIGGER MB_DG_TRG_AUTOS_UPD AFTER UPDATE ON MB_DG_AUTOS FOR EACH ROW
BEGIN
  DECLARE v_antes LONGTEXT;
  DECLARE v_despues LONGTEXT;
  SET v_antes   = JSON_OBJECT('id', OLD.id, 'marca', OLD.marca, 'nombre', OLD.nombre, 'carroceria', OLD.carroceria, 'color_base', OLD.color_base, 'activo', OLD.activo);
  SET v_despues = JSON_OBJECT('id', NEW.id, 'marca', NEW.marca, 'nombre', NEW.nombre, 'carroceria', NEW.carroceria, 'color_base', NEW.color_base, 'activo', NEW.activo);
  IF NOT (v_antes <=> v_despues) THEN      -- solo si algo cambió de verdad
    INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
    VALUES ('MB_DG_AUTOS', 'UPDATE', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), v_antes, v_despues);
  END IF;
END$$
CREATE TRIGGER MB_DG_TRG_AUTOS_DEL AFTER DELETE ON MB_DG_AUTOS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_AUTOS', 'DELETE', OLD.id, CAST(@app_usuario_id AS UNSIGNED), USER(), JSON_OBJECT('id', OLD.id, 'marca', OLD.marca, 'nombre', OLD.nombre, 'carroceria', OLD.carroceria, 'color_base', OLD.color_base, 'activo', OLD.activo), NULL);
END$$

-- MB_DG_COLORES
CREATE TRIGGER MB_DG_TRG_COLORES_INS AFTER INSERT ON MB_DG_COLORES FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_COLORES', 'INSERT', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), NULL, JSON_OBJECT('id', NEW.id, 'nombre', NEW.nombre, 'hex', NEW.hex));
END$$
CREATE TRIGGER MB_DG_TRG_COLORES_UPD AFTER UPDATE ON MB_DG_COLORES FOR EACH ROW
BEGIN
  DECLARE v_antes LONGTEXT;
  DECLARE v_despues LONGTEXT;
  SET v_antes   = JSON_OBJECT('id', OLD.id, 'nombre', OLD.nombre, 'hex', OLD.hex);
  SET v_despues = JSON_OBJECT('id', NEW.id, 'nombre', NEW.nombre, 'hex', NEW.hex);
  IF NOT (v_antes <=> v_despues) THEN      -- solo si algo cambió de verdad
    INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
    VALUES ('MB_DG_COLORES', 'UPDATE', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), v_antes, v_despues);
  END IF;
END$$
CREATE TRIGGER MB_DG_TRG_COLORES_DEL AFTER DELETE ON MB_DG_COLORES FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_COLORES', 'DELETE', OLD.id, CAST(@app_usuario_id AS UNSIGNED), USER(), JSON_OBJECT('id', OLD.id, 'nombre', OLD.nombre, 'hex', OLD.hex), NULL);
END$$

-- MB_DG_ACABADOS
CREATE TRIGGER MB_DG_TRG_ACABADOS_INS AFTER INSERT ON MB_DG_ACABADOS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_ACABADOS', 'INSERT', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), NULL, JSON_OBJECT('id', NEW.id, 'nombre', NEW.nombre, 'hex', NEW.hex));
END$$
CREATE TRIGGER MB_DG_TRG_ACABADOS_UPD AFTER UPDATE ON MB_DG_ACABADOS FOR EACH ROW
BEGIN
  DECLARE v_antes LONGTEXT;
  DECLARE v_despues LONGTEXT;
  SET v_antes   = JSON_OBJECT('id', OLD.id, 'nombre', OLD.nombre, 'hex', OLD.hex);
  SET v_despues = JSON_OBJECT('id', NEW.id, 'nombre', NEW.nombre, 'hex', NEW.hex);
  IF NOT (v_antes <=> v_despues) THEN      -- solo si algo cambió de verdad
    INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
    VALUES ('MB_DG_ACABADOS', 'UPDATE', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), v_antes, v_despues);
  END IF;
END$$
CREATE TRIGGER MB_DG_TRG_ACABADOS_DEL AFTER DELETE ON MB_DG_ACABADOS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_ACABADOS', 'DELETE', OLD.id, CAST(@app_usuario_id AS UNSIGNED), USER(), JSON_OBJECT('id', OLD.id, 'nombre', OLD.nombre, 'hex', OLD.hex), NULL);
END$$

-- MB_DG_RINES
CREATE TRIGGER MB_DG_TRG_RINES_INS AFTER INSERT ON MB_DG_RINES FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_RINES', 'INSERT', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), NULL, JSON_OBJECT('id', NEW.id, 'nombre', NEW.nombre, 'estilo', NEW.estilo, 'acabado_base', NEW.acabado_base, 'precio', NEW.precio, 'activo', NEW.activo));
END$$
CREATE TRIGGER MB_DG_TRG_RINES_UPD AFTER UPDATE ON MB_DG_RINES FOR EACH ROW
BEGIN
  DECLARE v_antes LONGTEXT;
  DECLARE v_despues LONGTEXT;
  SET v_antes   = JSON_OBJECT('id', OLD.id, 'nombre', OLD.nombre, 'estilo', OLD.estilo, 'acabado_base', OLD.acabado_base, 'precio', OLD.precio, 'activo', OLD.activo);
  SET v_despues = JSON_OBJECT('id', NEW.id, 'nombre', NEW.nombre, 'estilo', NEW.estilo, 'acabado_base', NEW.acabado_base, 'precio', NEW.precio, 'activo', NEW.activo);
  IF NOT (v_antes <=> v_despues) THEN      -- solo si algo cambió de verdad
    INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
    VALUES ('MB_DG_RINES', 'UPDATE', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), v_antes, v_despues);
  END IF;
END$$
CREATE TRIGGER MB_DG_TRG_RINES_DEL AFTER DELETE ON MB_DG_RINES FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_RINES', 'DELETE', OLD.id, CAST(@app_usuario_id AS UNSIGNED), USER(), JSON_OBJECT('id', OLD.id, 'nombre', OLD.nombre, 'estilo', OLD.estilo, 'acabado_base', OLD.acabado_base, 'precio', OLD.precio, 'activo', OLD.activo), NULL);
END$$

-- MB_DG_LLANTAS
CREATE TRIGGER MB_DG_TRG_LLANTAS_INS AFTER INSERT ON MB_DG_LLANTAS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_LLANTAS', 'INSERT', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), NULL, JSON_OBJECT('id', NEW.id, 'codigo', NEW.codigo, 'nombre', NEW.nombre, 'svg_radio', NEW.svg_radio, 'svg_radio_rin', NEW.svg_radio_rin, 'precio', NEW.precio, 'activo', NEW.activo));
END$$
CREATE TRIGGER MB_DG_TRG_LLANTAS_UPD AFTER UPDATE ON MB_DG_LLANTAS FOR EACH ROW
BEGIN
  DECLARE v_antes LONGTEXT;
  DECLARE v_despues LONGTEXT;
  SET v_antes   = JSON_OBJECT('id', OLD.id, 'codigo', OLD.codigo, 'nombre', OLD.nombre, 'svg_radio', OLD.svg_radio, 'svg_radio_rin', OLD.svg_radio_rin, 'precio', OLD.precio, 'activo', OLD.activo);
  SET v_despues = JSON_OBJECT('id', NEW.id, 'codigo', NEW.codigo, 'nombre', NEW.nombre, 'svg_radio', NEW.svg_radio, 'svg_radio_rin', NEW.svg_radio_rin, 'precio', NEW.precio, 'activo', NEW.activo);
  IF NOT (v_antes <=> v_despues) THEN      -- solo si algo cambió de verdad
    INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
    VALUES ('MB_DG_LLANTAS', 'UPDATE', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), v_antes, v_despues);
  END IF;
END$$
CREATE TRIGGER MB_DG_TRG_LLANTAS_DEL AFTER DELETE ON MB_DG_LLANTAS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_LLANTAS', 'DELETE', OLD.id, CAST(@app_usuario_id AS UNSIGNED), USER(), JSON_OBJECT('id', OLD.id, 'codigo', OLD.codigo, 'nombre', OLD.nombre, 'svg_radio', OLD.svg_radio, 'svg_radio_rin', OLD.svg_radio_rin, 'precio', OLD.precio, 'activo', OLD.activo), NULL);
END$$

-- MB_DG_MEDIDAS
CREATE TRIGGER MB_DG_TRG_MEDIDAS_INS AFTER INSERT ON MB_DG_MEDIDAS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_MEDIDAS', 'INSERT', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), NULL, JSON_OBJECT('id', NEW.id, 'tipo', NEW.tipo, 'etiqueta', NEW.etiqueta, 'factor', NEW.factor));
END$$
CREATE TRIGGER MB_DG_TRG_MEDIDAS_UPD AFTER UPDATE ON MB_DG_MEDIDAS FOR EACH ROW
BEGIN
  DECLARE v_antes LONGTEXT;
  DECLARE v_despues LONGTEXT;
  SET v_antes   = JSON_OBJECT('id', OLD.id, 'tipo', OLD.tipo, 'etiqueta', OLD.etiqueta, 'factor', OLD.factor);
  SET v_despues = JSON_OBJECT('id', NEW.id, 'tipo', NEW.tipo, 'etiqueta', NEW.etiqueta, 'factor', NEW.factor);
  IF NOT (v_antes <=> v_despues) THEN      -- solo si algo cambió de verdad
    INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
    VALUES ('MB_DG_MEDIDAS', 'UPDATE', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), v_antes, v_despues);
  END IF;
END$$
CREATE TRIGGER MB_DG_TRG_MEDIDAS_DEL AFTER DELETE ON MB_DG_MEDIDAS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_MEDIDAS', 'DELETE', OLD.id, CAST(@app_usuario_id AS UNSIGNED), USER(), JSON_OBJECT('id', OLD.id, 'tipo', OLD.tipo, 'etiqueta', OLD.etiqueta, 'factor', OLD.factor), NULL);
END$$

-- MB_DG_CONFIGURACIONES
CREATE TRIGGER MB_DG_TRG_CONFIGURACIONES_INS AFTER INSERT ON MB_DG_CONFIGURACIONES FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_CONFIGURACIONES', 'INSERT', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), NULL, JSON_OBJECT('id', NEW.id, 'tipo', NEW.tipo, 'nombre', NEW.nombre, 'detalle', NEW.detalle, 'precio_unitario', NEW.precio_unitario, 'auto_id', NEW.auto_id, 'color_id', NEW.color_id, 'rin_id', NEW.rin_id, 'acabado_id', NEW.acabado_id, 'medida_rin_id', NEW.medida_rin_id, 'ancho_rin', NEW.ancho_rin, 'llanta_id', NEW.llanta_id, 'medida_llanta_id', NEW.medida_llanta_id, 'creado_en', NEW.creado_en));
END$$
CREATE TRIGGER MB_DG_TRG_CONFIGURACIONES_UPD AFTER UPDATE ON MB_DG_CONFIGURACIONES FOR EACH ROW
BEGIN
  DECLARE v_antes LONGTEXT;
  DECLARE v_despues LONGTEXT;
  SET v_antes   = JSON_OBJECT('id', OLD.id, 'tipo', OLD.tipo, 'nombre', OLD.nombre, 'detalle', OLD.detalle, 'precio_unitario', OLD.precio_unitario, 'auto_id', OLD.auto_id, 'color_id', OLD.color_id, 'rin_id', OLD.rin_id, 'acabado_id', OLD.acabado_id, 'medida_rin_id', OLD.medida_rin_id, 'ancho_rin', OLD.ancho_rin, 'llanta_id', OLD.llanta_id, 'medida_llanta_id', OLD.medida_llanta_id, 'creado_en', OLD.creado_en);
  SET v_despues = JSON_OBJECT('id', NEW.id, 'tipo', NEW.tipo, 'nombre', NEW.nombre, 'detalle', NEW.detalle, 'precio_unitario', NEW.precio_unitario, 'auto_id', NEW.auto_id, 'color_id', NEW.color_id, 'rin_id', NEW.rin_id, 'acabado_id', NEW.acabado_id, 'medida_rin_id', NEW.medida_rin_id, 'ancho_rin', NEW.ancho_rin, 'llanta_id', NEW.llanta_id, 'medida_llanta_id', NEW.medida_llanta_id, 'creado_en', NEW.creado_en);
  IF NOT (v_antes <=> v_despues) THEN      -- solo si algo cambió de verdad
    INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
    VALUES ('MB_DG_CONFIGURACIONES', 'UPDATE', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), v_antes, v_despues);
  END IF;
END$$
CREATE TRIGGER MB_DG_TRG_CONFIGURACIONES_DEL AFTER DELETE ON MB_DG_CONFIGURACIONES FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_CONFIGURACIONES', 'DELETE', OLD.id, CAST(@app_usuario_id AS UNSIGNED), USER(), JSON_OBJECT('id', OLD.id, 'tipo', OLD.tipo, 'nombre', OLD.nombre, 'detalle', OLD.detalle, 'precio_unitario', OLD.precio_unitario, 'auto_id', OLD.auto_id, 'color_id', OLD.color_id, 'rin_id', OLD.rin_id, 'acabado_id', OLD.acabado_id, 'medida_rin_id', OLD.medida_rin_id, 'ancho_rin', OLD.ancho_rin, 'llanta_id', OLD.llanta_id, 'medida_llanta_id', OLD.medida_llanta_id, 'creado_en', OLD.creado_en), NULL);
END$$

-- MB_DG_PEDIDOS
CREATE TRIGGER MB_DG_TRG_PEDIDOS_INS AFTER INSERT ON MB_DG_PEDIDOS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_PEDIDOS', 'INSERT', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), NULL, JSON_OBJECT('id', NEW.id, 'codigo', NEW.codigo, 'usuario_id', NEW.usuario_id, 'nombre_completo', NEW.nombre_completo, 'direccion', NEW.direccion, 'ciudad', NEW.ciudad, 'departamento', NEW.departamento, 'telefono', NEW.telefono, 'subtotal', NEW.subtotal, 'costo_envio', NEW.costo_envio, 'total', NEW.total, 'estado', NEW.estado, 'creado_en', NEW.creado_en));
END$$
CREATE TRIGGER MB_DG_TRG_PEDIDOS_UPD AFTER UPDATE ON MB_DG_PEDIDOS FOR EACH ROW
BEGIN
  DECLARE v_antes LONGTEXT;
  DECLARE v_despues LONGTEXT;
  SET v_antes   = JSON_OBJECT('id', OLD.id, 'codigo', OLD.codigo, 'usuario_id', OLD.usuario_id, 'nombre_completo', OLD.nombre_completo, 'direccion', OLD.direccion, 'ciudad', OLD.ciudad, 'departamento', OLD.departamento, 'telefono', OLD.telefono, 'subtotal', OLD.subtotal, 'costo_envio', OLD.costo_envio, 'total', OLD.total, 'estado', OLD.estado, 'creado_en', OLD.creado_en);
  SET v_despues = JSON_OBJECT('id', NEW.id, 'codigo', NEW.codigo, 'usuario_id', NEW.usuario_id, 'nombre_completo', NEW.nombre_completo, 'direccion', NEW.direccion, 'ciudad', NEW.ciudad, 'departamento', NEW.departamento, 'telefono', NEW.telefono, 'subtotal', NEW.subtotal, 'costo_envio', NEW.costo_envio, 'total', NEW.total, 'estado', NEW.estado, 'creado_en', NEW.creado_en);
  IF NOT (v_antes <=> v_despues) THEN      -- solo si algo cambió de verdad
    INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
    VALUES ('MB_DG_PEDIDOS', 'UPDATE', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), v_antes, v_despues);
  END IF;
END$$
CREATE TRIGGER MB_DG_TRG_PEDIDOS_DEL AFTER DELETE ON MB_DG_PEDIDOS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_PEDIDOS', 'DELETE', OLD.id, CAST(@app_usuario_id AS UNSIGNED), USER(), JSON_OBJECT('id', OLD.id, 'codigo', OLD.codigo, 'usuario_id', OLD.usuario_id, 'nombre_completo', OLD.nombre_completo, 'direccion', OLD.direccion, 'ciudad', OLD.ciudad, 'departamento', OLD.departamento, 'telefono', OLD.telefono, 'subtotal', OLD.subtotal, 'costo_envio', OLD.costo_envio, 'total', OLD.total, 'estado', OLD.estado, 'creado_en', OLD.creado_en), NULL);
END$$
-- Borrar un pedido borra sus renglones; MySQL no activa triggers en borrados en cascada,
-- por eso se borran aquí explícitamente (así cada renglón queda en la auditoría).
CREATE TRIGGER MB_DG_TRG_PEDIDOS_DEL_ITEMS BEFORE DELETE ON MB_DG_PEDIDOS FOR EACH ROW
BEGIN
  DELETE FROM MB_DG_PEDIDO_ITEMS WHERE pedido_id = OLD.id;
END$$

-- MB_DG_PEDIDO_ITEMS
CREATE TRIGGER MB_DG_TRG_PEDIDO_ITEMS_INS AFTER INSERT ON MB_DG_PEDIDO_ITEMS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_PEDIDO_ITEMS', 'INSERT', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), NULL, JSON_OBJECT('id', NEW.id, 'pedido_id', NEW.pedido_id, 'configuracion_id', NEW.configuracion_id, 'cantidad', NEW.cantidad));
END$$
CREATE TRIGGER MB_DG_TRG_PEDIDO_ITEMS_UPD AFTER UPDATE ON MB_DG_PEDIDO_ITEMS FOR EACH ROW
BEGIN
  DECLARE v_antes LONGTEXT;
  DECLARE v_despues LONGTEXT;
  SET v_antes   = JSON_OBJECT('id', OLD.id, 'pedido_id', OLD.pedido_id, 'configuracion_id', OLD.configuracion_id, 'cantidad', OLD.cantidad);
  SET v_despues = JSON_OBJECT('id', NEW.id, 'pedido_id', NEW.pedido_id, 'configuracion_id', NEW.configuracion_id, 'cantidad', NEW.cantidad);
  IF NOT (v_antes <=> v_despues) THEN      -- solo si algo cambió de verdad
    INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
    VALUES ('MB_DG_PEDIDO_ITEMS', 'UPDATE', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), v_antes, v_despues);
  END IF;
END$$
CREATE TRIGGER MB_DG_TRG_PEDIDO_ITEMS_DEL AFTER DELETE ON MB_DG_PEDIDO_ITEMS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_PEDIDO_ITEMS', 'DELETE', OLD.id, CAST(@app_usuario_id AS UNSIGNED), USER(), JSON_OBJECT('id', OLD.id, 'pedido_id', OLD.pedido_id, 'configuracion_id', OLD.configuracion_id, 'cantidad', OLD.cantidad), NULL);
END$$

-- MB_DG_PAGOS
CREATE TRIGGER MB_DG_TRG_PAGOS_INS AFTER INSERT ON MB_DG_PAGOS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_PAGOS', 'INSERT', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), NULL, JSON_OBJECT('id', NEW.id, 'pedido_id', NEW.pedido_id, 'pasarela', NEW.pasarela, 'referencia_externa', NEW.referencia_externa, 'estado', NEW.estado, 'monto', NEW.monto, 'moneda', NEW.moneda, 'metodo_tipo', NEW.metodo_tipo, 'marca', NEW.marca, 'ultimos4', NEW.ultimos4, 'creado_en', NEW.creado_en));
END$$
CREATE TRIGGER MB_DG_TRG_PAGOS_UPD AFTER UPDATE ON MB_DG_PAGOS FOR EACH ROW
BEGIN
  DECLARE v_antes LONGTEXT;
  DECLARE v_despues LONGTEXT;
  SET v_antes   = JSON_OBJECT('id', OLD.id, 'pedido_id', OLD.pedido_id, 'pasarela', OLD.pasarela, 'referencia_externa', OLD.referencia_externa, 'estado', OLD.estado, 'monto', OLD.monto, 'moneda', OLD.moneda, 'metodo_tipo', OLD.metodo_tipo, 'marca', OLD.marca, 'ultimos4', OLD.ultimos4, 'creado_en', OLD.creado_en);
  SET v_despues = JSON_OBJECT('id', NEW.id, 'pedido_id', NEW.pedido_id, 'pasarela', NEW.pasarela, 'referencia_externa', NEW.referencia_externa, 'estado', NEW.estado, 'monto', NEW.monto, 'moneda', NEW.moneda, 'metodo_tipo', NEW.metodo_tipo, 'marca', NEW.marca, 'ultimos4', NEW.ultimos4, 'creado_en', NEW.creado_en);
  IF NOT (v_antes <=> v_despues) THEN      -- solo si algo cambió de verdad
    INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
    VALUES ('MB_DG_PAGOS', 'UPDATE', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), v_antes, v_despues);
  END IF;
END$$
CREATE TRIGGER MB_DG_TRG_PAGOS_DEL AFTER DELETE ON MB_DG_PAGOS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_PAGOS', 'DELETE', OLD.id, CAST(@app_usuario_id AS UNSIGNED), USER(), JSON_OBJECT('id', OLD.id, 'pedido_id', OLD.pedido_id, 'pasarela', OLD.pasarela, 'referencia_externa', OLD.referencia_externa, 'estado', OLD.estado, 'monto', OLD.monto, 'moneda', OLD.moneda, 'metodo_tipo', OLD.metodo_tipo, 'marca', OLD.marca, 'ultimos4', OLD.ultimos4, 'creado_en', OLD.creado_en), NULL);
END$$

DELIMITER ;

-- =====================================================================
--  DATOS DE EJEMPLO (catálogo, clientes, administrador y 13 pedidos)
--  Las contraseñas están cifradas con bcrypt; no hay claves en texto plano.
--    Administrador:  admin@autorim.com / Admin12345 / código AUTORIM-2026
--    Clientes:       cliente1@demo.com, cliente2@demo.com, cliente3@demo.com / Cliente123
--  CAMBIA los datos del administrador antes de publicar la web (npm run crear-admin).
-- =====================================================================
SET @app_usuario_id = 1;   -- los cambios de esta carga quedan auditados a nombre del admin

INSERT INTO MB_DG_USUARIOS (id, email, password_hash, rol, codigo_acceso_hash) VALUES
  (1, 'admin@autorim.com', '$2a$10$QBzoXsZ6OSJpxsMy/dHglui2IFrgR1DVIjwT79TEkcfyih5oUYyGK', 'admin', '$2a$10$TmjNlp/04DHQH5Vck6DGVOpN1OLzFXXh41oJswSjrENUWtlVMaewy'),
  (2, 'cliente1@demo.com', '$2a$10$7fC4MvPNNtQfELaWn7kD7.nbMg870/1qPJT4XcUkMbKTdt710XgBm', 'cliente', NULL),
  (3, 'cliente2@demo.com', '$2a$10$7fC4MvPNNtQfELaWn7kD7.nbMg870/1qPJT4XcUkMbKTdt710XgBm', 'cliente', NULL),
  (4, 'cliente3@demo.com', '$2a$10$7fC4MvPNNtQfELaWn7kD7.nbMg870/1qPJT4XcUkMbKTdt710XgBm', 'cliente', NULL);

INSERT INTO MB_DG_AUTOS (id, marca, nombre, carroceria, color_base) VALUES
  (1, 'Vektra', 'Vektra GT-R', 'gt', '#1f2933'),
  (2, 'Vektra', 'Vektra RS Coupé', 'coupe', '#8a1c1c'),
  (3, 'Zenor', 'Zenor Muscle V8', 'muscle', '#2b2b2b'),
  (4, 'Zenor', 'Zenor Stallion', 'muscle', '#b8860b'),
  (5, 'Kairo', 'Kairo Sprint', 'coupe', '#e5e7eb'),
  (6, 'Kairo', 'Kairo Cross SUV', 'suv', '#374151'),
  (7, 'Nordik', 'Nordik GT Turbo', 'gt', '#0f4c81'),
  (8, 'Nordik', 'Nordik Ranger', 'suv', '#4b5d3a');

INSERT INTO MB_DG_COLORES (id, nombre, hex) VALUES
  (1, 'Rojo Fuego', '#e11d2e'),
  (2, 'Negro Ónix', '#111111'),
  (3, 'Blanco Perla', '#f5f5f5'),
  (4, 'Azul Eléctrico', '#1d4ed8'),
  (5, 'Gris Cemento', '#6b7280'),
  (6, 'Amarillo Sol', '#facc15'),
  (7, 'Verde Militar', '#3f6212'),
  (8, 'Naranja Lava', '#ea580c');

INSERT INTO MB_DG_ACABADOS (id, nombre, hex) VALUES
  (1, 'Negro Mate', '#1a1a1a'),
  (2, 'Plata', '#c0c0c0'),
  (3, 'Bronce', '#8c6a3d'),
  (4, 'Oro', '#d4af37'),
  (5, 'Gunmetal', '#4b5563'),
  (6, 'Rojo Candy', '#b91c1c');

INSERT INTO MB_DG_RINES (id, nombre, estilo, acabado_base, precio) VALUES
  (1, 'Apex Five', 'five', '#c0c0c0', 1490000),
  (2, 'Rally Mesh', 'mesh', '#1a1a1a', 1890000),
  (3, 'Turbo Fan', 'turbine', '#4b5563', 2290000),
  (4, 'Multi Spoke X', 'multi', '#c0c0c0', 2590000),
  (5, 'Drift Five', 'five', '#1a1a1a', 1690000),
  (6, 'Royale Mesh', 'mesh', '#d4af37', 3190000);

INSERT INTO MB_DG_LLANTAS (id, codigo, nombre, svg_radio, svg_radio_rin, precio) VALUES
  (1, 'sport', 'Sport', 100, 64, 1200000),
  (2, 'off', 'Off-Road', 108, 62, 1650000),
  (3, 'pre', 'Premium', 104, 66, 2200000);

INSERT INTO MB_DG_MEDIDAS (id, tipo, etiqueta, factor) VALUES
  (1, 'rin', '17"', 1.0),
  (2, 'rin', '18"', 1.08),
  (3, 'rin', '19"', 1.18),
  (4, 'rin', '20"', 1.3),
  (5, 'rin', '21"', 1.45),
  (6, 'llanta', '225/45 R17', 1.0),
  (7, 'llanta', '245/40 R18', 1.1),
  (8, 'llanta', '255/35 R19', 1.22),
  (9, 'llanta', '265/30 R20', 1.35),
  (10, 'llanta', '275/30 R21', 1.5);

-- 13 pedidos de demostración (para que los reportes de ventas tengan información)
INSERT INTO MB_DG_CONFIGURACIONES (id, tipo, nombre, detalle, precio_unitario, auto_id, color_id, rin_id, acabado_id, medida_rin_id, ancho_rin, llanta_id, medida_llanta_id) VALUES
  (1, 'kit', 'Nordik GT Turbo', 'Rojo Fuego · Apex Five · Premium', 3690000, 7, 1, 1, NULL, NULL, NULL, 3, NULL),
  (2, 'rines', 'Drift Five', 'Set de 4 · Gunmetal · 17" · 7.5J', 1690000, NULL, NULL, 5, 5, 1, '7.5J', NULL, NULL),
  (3, 'rines', 'Multi Spoke X', 'Set de 4 · Plata · 17" · 7.5J', 2590000, NULL, NULL, 4, 2, 1, '7.5J', NULL, NULL),
  (4, 'llantas', 'Sport', 'Set de 4 · 245/40 R18', 1320000, NULL, NULL, NULL, NULL, NULL, NULL, 1, 7),
  (5, 'kit', 'Zenor Stallion', 'Rojo Fuego · Drift Five · Sport', 2890000, 4, 1, 5, NULL, NULL, NULL, 1, NULL),
  (6, 'rines', 'Rally Mesh', 'Set de 4 · Negro Mate · 21" · 9.5J', 2740000, NULL, NULL, 2, 1, 5, '9.5J', NULL, NULL),
  (7, 'llantas', 'Premium', 'Set de 4 · 245/40 R18', 2420000, NULL, NULL, NULL, NULL, NULL, NULL, 3, 7),
  (8, 'rines', 'Apex Five', 'Set de 4 · Rojo Candy · 21" · 7.5J', 2160000, NULL, NULL, 1, 6, 5, '7.5J', NULL, NULL),
  (9, 'llantas', 'Sport', 'Set de 4 · 265/30 R20', 1620000, NULL, NULL, NULL, NULL, NULL, NULL, 1, 9),
  (10, 'rines', 'Drift Five', 'Set de 4 · Bronce · 20" · 8.5J', 2197000, NULL, NULL, 5, 3, 4, '8.5J', NULL, NULL),
  (11, 'kit', 'Zenor Stallion', 'Negro Ónix · Drift Five · Off-Road', 3340000, 4, 2, 5, NULL, NULL, NULL, 2, NULL),
  (12, 'llantas', 'Off-Road', 'Set de 4 · 255/35 R19', 2013000, NULL, NULL, NULL, NULL, NULL, NULL, 2, 8),
  (13, 'kit', 'Nordik GT Turbo', 'Blanco Perla · Turbo Fan · Sport', 3490000, 7, 3, 3, NULL, NULL, NULL, 1, NULL),
  (14, 'kit', 'Vektra RS Coupé', 'Amarillo Sol · Turbo Fan · Premium', 4490000, 2, 6, 3, NULL, NULL, NULL, 3, NULL),
  (15, 'llantas', 'Off-Road', 'Set de 4 · 275/30 R21', 2475000, NULL, NULL, NULL, NULL, NULL, NULL, 2, 10),
  (16, 'kit', 'Vektra RS Coupé', 'Gris Cemento · Multi Spoke X · Premium', 4790000, 2, 5, 4, NULL, NULL, NULL, 3, NULL),
  (17, 'llantas', 'Premium', 'Set de 4 · 255/35 R19', 2684000, NULL, NULL, NULL, NULL, NULL, NULL, 3, 8),
  (18, 'llantas', 'Off-Road', 'Set de 4 · 255/35 R19', 2013000, NULL, NULL, NULL, NULL, NULL, NULL, 2, 8),
  (19, 'rines', 'Turbo Fan', 'Set de 4 · Gunmetal · 18" · 7.5J', 2473000, NULL, NULL, 3, 5, 2, '7.5J', NULL, NULL),
  (20, 'kit', 'Kairo Sprint', 'Blanco Perla · Royale Mesh · Sport', 4390000, 5, 3, 6, NULL, NULL, NULL, 1, NULL),
  (21, 'rines', 'Apex Five', 'Set de 4 · Oro · 18" · 8.5J', 1609000, NULL, NULL, 1, 4, 2, '8.5J', NULL, NULL),
  (22, 'kit', 'Nordik GT Turbo', 'Gris Cemento · Royale Mesh · Off-Road', 4840000, 7, 5, 6, NULL, NULL, NULL, 2, NULL),
  (23, 'llantas', 'Off-Road', 'Set de 4 · 245/40 R18', 1815000, NULL, NULL, NULL, NULL, NULL, NULL, 2, 7),
  (24, 'kit', 'Zenor Muscle V8', 'Azul Eléctrico · Royale Mesh · Sport', 4390000, 3, 4, 6, NULL, NULL, NULL, 1, NULL);

INSERT INTO MB_DG_PEDIDOS (id, codigo, usuario_id, nombre_completo, direccion, ciudad, departamento, telefono, subtotal, costo_envio, total, estado, creado_en) VALUES
  (1, 'AR-100001', 2, 'Carlos Pérez', 'Cra 15 #93-20', 'Bogotá', 'Cundinamarca', '3001112233', 5380000, 25000, 5405000, 'entregado', '2026-01-14 15:30:00'),
  (2, 'AR-107920', 3, 'Laura Gómez', 'Cl 10 #5-30', 'Medellín', 'Antioquia', '3012223344', 5180000, 25000, 5205000, 'entregado', '2026-02-03 15:30:00'),
  (3, 'AR-115839', 4, 'Andrés Rojas', 'Av 6N #25-10', 'Cali', 'Valle del Cauca', '3023334455', 1320000, 25000, 1345000, 'enviado', '2026-02-21 15:30:00'),
  (4, 'AR-123758', 2, 'Carlos Pérez', 'Cra 15 #93-20', 'Bogotá', 'Cundinamarca', '3001112233', 8050000, 25000, 8075000, 'pagado', '2026-03-09 15:30:00'),
  (5, 'AR-131677', 3, 'Laura Gómez', 'Cl 10 #5-30', 'Medellín', 'Antioquia', '3012223344', 5400000, 25000, 5425000, 'entregado', '2026-04-17 15:30:00'),
  (6, 'AR-139596', 4, 'Andrés Rojas', 'Av 6N #25-10', 'Cali', 'Valle del Cauca', '3023334455', 8877000, 25000, 8902000, 'pagado', '2026-05-05 15:30:00'),
  (7, 'AR-147515', 2, 'Carlos Pérez', 'Cra 15 #93-20', 'Bogotá', 'Cundinamarca', '3001112233', 8993000, 25000, 9018000, 'cancelado', '2026-05-28 15:30:00'),
  (8, 'AR-155434', 3, 'Laura Gómez', 'Cl 10 #5-30', 'Medellín', 'Antioquia', '3012223344', 14230000, 25000, 14255000, 'enviado', '2026-06-12 15:30:00'),
  (9, 'AR-163353', 4, 'Andrés Rojas', 'Av 6N #25-10', 'Cali', 'Valle del Cauca', '3023334455', 5368000, 25000, 5393000, 'entregado', '2026-07-08 15:30:00'),
  (10, 'AR-171272', 2, 'Carlos Pérez', 'Cra 15 #93-20', 'Bogotá', 'Cundinamarca', '3001112233', 6959000, 25000, 6984000, 'pendiente', '2026-08-19 15:30:00'),
  (11, 'AR-179191', 3, 'Laura Gómez', 'Cl 10 #5-30', 'Medellín', 'Antioquia', '3012223344', 8780000, 25000, 8805000, 'pagado', '2026-09-23 15:30:00'),
  (12, 'AR-187110', 4, 'Andrés Rojas', 'Av 6N #25-10', 'Cali', 'Valle del Cauca', '3023334455', 8264000, 25000, 8289000, 'enviado', '2026-10-15 15:30:00'),
  (13, 'AR-195029', 2, 'Carlos Pérez', 'Cra 15 #93-20', 'Bogotá', 'Cundinamarca', '3001112233', 4390000, 25000, 4415000, 'pagado', '2026-11-10 15:30:00');

INSERT INTO MB_DG_PEDIDO_ITEMS (id, pedido_id, configuracion_id, cantidad) VALUES
  (1, 1, 1, 1),
  (2, 1, 2, 1),
  (3, 2, 3, 2),
  (4, 3, 4, 1),
  (5, 4, 5, 1),
  (6, 4, 6, 1),
  (7, 4, 7, 1),
  (8, 5, 8, 1),
  (9, 5, 9, 2),
  (10, 6, 10, 1),
  (11, 6, 11, 2),
  (12, 7, 12, 1),
  (13, 7, 13, 2),
  (14, 8, 14, 1),
  (15, 8, 15, 2),
  (16, 8, 16, 1),
  (17, 9, 17, 2),
  (18, 10, 18, 1),
  (19, 10, 19, 2),
  (20, 11, 20, 2),
  (21, 12, 21, 1),
  (22, 12, 22, 1),
  (23, 12, 23, 1),
  (24, 13, 24, 1);

INSERT INTO MB_DG_PAGOS (id, pedido_id, pasarela, referencia_externa, estado, monto, metodo_tipo, marca, ultimos4, creado_en) VALUES
  (1, 1, 'simulada', 'SIM-AR-100001', 'aprobado', 5405000, 'tarjeta', 'visa', '4242', '2026-01-14 15:31:00'),
  (2, 2, 'simulada', 'SIM-AR-107920', 'aprobado', 5205000, 'tarjeta', 'visa', '4242', '2026-02-03 15:31:00'),
  (3, 3, 'simulada', 'SIM-AR-115839', 'aprobado', 1345000, 'tarjeta', 'visa', '4242', '2026-02-21 15:31:00'),
  (4, 4, 'simulada', 'SIM-AR-123758', 'aprobado', 8075000, 'tarjeta', 'visa', '4242', '2026-03-09 15:31:00'),
  (5, 5, 'simulada', 'SIM-AR-131677', 'aprobado', 5425000, 'tarjeta', 'visa', '4242', '2026-04-17 15:31:00'),
  (6, 6, 'simulada', 'SIM-AR-139596', 'aprobado', 8902000, 'tarjeta', 'visa', '4242', '2026-05-05 15:31:00'),
  (7, 7, 'simulada', 'SIM-AR-147515', 'rechazado', 9018000, 'tarjeta', 'visa', '4242', '2026-05-28 15:31:00'),
  (8, 8, 'simulada', 'SIM-AR-155434', 'aprobado', 14255000, 'tarjeta', 'visa', '4242', '2026-06-12 15:31:00'),
  (9, 9, 'simulada', 'SIM-AR-163353', 'aprobado', 5393000, 'tarjeta', 'visa', '4242', '2026-07-08 15:31:00'),
  (10, 10, 'simulada', 'SIM-AR-171272', 'pendiente', 6984000, 'tarjeta', 'visa', '4242', '2026-08-19 15:31:00'),
  (11, 11, 'simulada', 'SIM-AR-179191', 'aprobado', 8805000, 'tarjeta', 'visa', '4242', '2026-09-23 15:31:00'),
  (12, 12, 'simulada', 'SIM-AR-187110', 'aprobado', 8289000, 'tarjeta', 'visa', '4242', '2026-10-15 15:31:00'),
  (13, 13, 'simulada', 'SIM-AR-195029', 'aprobado', 4415000, 'tarjeta', 'visa', '4242', '2026-11-10 15:31:00');

SET @app_usuario_id = NULL;