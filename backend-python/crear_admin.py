import sys
from auth import hash_pw
from db import engine, run

if len(sys.argv) != 4:
    sys.exit('Uso: python crear_admin.py <correo> <contraseña> <código de acceso>')
email, password, code = sys.argv[1].strip().lower(), sys.argv[2], sys.argv[3]
if len(password) < 8:
    sys.exit('Usa una contraseña de al menos 8 caracteres.')
with engine.begin() as c:
    run(c, """INSERT INTO MB_DG_USUARIOS (email, password_hash, rol, codigo_acceso_hash) VALUES (?, ?, 'admin', ?)
              ON DUPLICATE KEY UPDATE password_hash = VALUES(password_hash), rol = 'admin', codigo_acceso_hash = VALUES(codigo_acceso_hash)""",
        (email, hash_pw(password), hash_pw(code)))
print(f'Administrador listo: {email}')
