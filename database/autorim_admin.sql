-- =====================================================================
--  AutoRim · Administrador inicial (pegar/importar en phpMyAdmin)
--  Importar DESPUÉS de autorim.sql y autorim_insert.sql.
--  Correo:            admin@autorim.com
--  Contraseña:        Admin12345
--  Código de acceso:  AUTORIM-2026
--  CAMBIA estos datos antes de publicar la web (npm run crear-admin).
--  Se puede repetir: si el correo ya existe, solo lo actualiza.
-- =====================================================================
USE autorim;

INSERT INTO MB_DG_USUARIOS (email, password_hash, rol, codigo_acceso_hash)
VALUES ('admin@autorim.com',
        '$2a$10$QBzoXsZ6OSJpxsMy/dHglui2IFrgR1DVIjwT79TEkcfyih5oUYyGK',
        'admin',
        '$2a$10$TmjNlp/04DHQH5Vck6DGVOpN1OLzFXXh41oJswSjrENUWtlVMaewy')
ON DUPLICATE KEY UPDATE password_hash = VALUES(password_hash), rol = 'admin', codigo_acceso_hash = VALUES(codigo_acceso_hash);
