-- =====================================================================
--  AutoRim · Tabla de PAGOS (MySQL 8 / MariaDB 10.5+)
--  Importar DESPUÉS de autorim.sql (estructura) y autorim_insert.sql (datos).
--  Es segura de repetir: no duplica tabla, triggers ni datos de prueba.
--  Nunca se guarda número completo de tarjeta ni CVV: solo marca y últimos 4.
--  Un pedido puede tener varios pagos (reintentos, reembolsos).
--  No hay ON DELETE CASCADE a propósito: un pedido con pagos no se puede borrar.
-- =====================================================================
USE autorim;

CREATE TABLE IF NOT EXISTS MB_DG_PAGOS (
  id                  INT AUTO_INCREMENT NOT NULL,
  pedido_id           INT NOT NULL,
  pasarela            VARCHAR(30) NOT NULL,            -- 'simulada', 'wompi', 'payu'...
  referencia_externa  VARCHAR(80) NULL,                -- id de la transacción en la pasarela
  estado              ENUM('pendiente','aprobado','rechazado','reembolsado') NOT NULL DEFAULT 'pendiente',
  monto               INT NOT NULL,                    -- COP, sin decimales
  moneda              CHAR(3) NOT NULL DEFAULT 'COP',
  metodo_tipo         ENUM('tarjeta','pse','nequi') NOT NULL DEFAULT 'tarjeta',
  marca               VARCHAR(20) NULL,                -- 'visa', 'mastercard'
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
--  TRIGGERS DE AUDITORÍA (mismo patrón que las demás tablas)
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS MB_DG_TRG_PAGOS_INS;
DROP TRIGGER IF EXISTS MB_DG_TRG_PAGOS_UPD;
DROP TRIGGER IF EXISTS MB_DG_TRG_PAGOS_DEL;

DELIMITER $$
CREATE TRIGGER MB_DG_TRG_PAGOS_INS AFTER INSERT ON MB_DG_PAGOS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_PAGOS', 'INSERT', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), NULL,
          JSON_OBJECT('id', NEW.id, 'pedido_id', NEW.pedido_id, 'pasarela', NEW.pasarela, 'referencia_externa', NEW.referencia_externa, 'estado', NEW.estado, 'monto', NEW.monto, 'moneda', NEW.moneda, 'metodo_tipo', NEW.metodo_tipo, 'marca', NEW.marca, 'ultimos4', NEW.ultimos4, 'creado_en', NEW.creado_en));
END$$
CREATE TRIGGER MB_DG_TRG_PAGOS_UPD AFTER UPDATE ON MB_DG_PAGOS FOR EACH ROW
BEGIN
  DECLARE v_antes LONGTEXT;
  DECLARE v_despues LONGTEXT;
  SET v_antes   = JSON_OBJECT('id', OLD.id, 'pedido_id', OLD.pedido_id, 'pasarela', OLD.pasarela, 'referencia_externa', OLD.referencia_externa, 'estado', OLD.estado, 'monto', OLD.monto, 'moneda', OLD.moneda, 'metodo_tipo', OLD.metodo_tipo, 'marca', OLD.marca, 'ultimos4', OLD.ultimos4, 'creado_en', OLD.creado_en);
  SET v_despues = JSON_OBJECT('id', NEW.id, 'pedido_id', NEW.pedido_id, 'pasarela', NEW.pasarela, 'referencia_externa', NEW.referencia_externa, 'estado', NEW.estado, 'monto', NEW.monto, 'moneda', NEW.moneda, 'metodo_tipo', NEW.metodo_tipo, 'marca', NEW.marca, 'ultimos4', NEW.ultimos4, 'creado_en', NEW.creado_en);
  IF NOT (v_antes <=> v_despues) THEN
    INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
    VALUES ('MB_DG_PAGOS', 'UPDATE', NEW.id, CAST(@app_usuario_id AS UNSIGNED), USER(), v_antes, v_despues);
  END IF;
END$$
CREATE TRIGGER MB_DG_TRG_PAGOS_DEL AFTER DELETE ON MB_DG_PAGOS FOR EACH ROW
BEGIN
  INSERT INTO MB_DG_AUDITORIA (tabla, operacion, registro_id, usuario_app, usuario_bd, datos_anteriores, datos_nuevos)
  VALUES ('MB_DG_PAGOS', 'DELETE', OLD.id, CAST(@app_usuario_id AS UNSIGNED), USER(),
          JSON_OBJECT('id', OLD.id, 'pedido_id', OLD.pedido_id, 'pasarela', OLD.pasarela, 'referencia_externa', OLD.referencia_externa, 'estado', OLD.estado, 'monto', OLD.monto, 'moneda', OLD.moneda, 'metodo_tipo', OLD.metodo_tipo, 'marca', OLD.marca, 'ultimos4', OLD.ultimos4, 'creado_en', OLD.creado_en), NULL);
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
--  DATOS DE PRUEBA: un pago por cada pedido que ya existe (solo si aún no tiene).
--  pendiente -> pendiente · cancelado -> rechazado · el resto -> aprobado
-- ---------------------------------------------------------------------
INSERT INTO MB_DG_PAGOS (pedido_id, pasarela, referencia_externa, estado, monto, metodo_tipo, marca, ultimos4)
SELECT p.id, 'simulada', CONCAT('SIM-', p.codigo),
       CASE p.estado WHEN 'pendiente' THEN 'pendiente' WHEN 'cancelado' THEN 'rechazado' ELSE 'aprobado' END,
       p.total, 'tarjeta', 'visa', '4242'
FROM MB_DG_PEDIDOS p
WHERE NOT EXISTS (SELECT 1 FROM MB_DG_PAGOS g WHERE g.pedido_id = p.id);
