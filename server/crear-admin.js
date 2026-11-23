// Crea (o actualiza) un administrador con contraseña y código de acceso hasheados.
//   node server/crear-admin.js correo@dominio.com "contraseña" "CODIGO"
import 'dotenv/config'
import bcrypt from 'bcryptjs'
import { pool } from './db.js'

const [email, password, code] = process.argv.slice(2)
if (!email || !password || !code) {
  console.error('Uso: node server/crear-admin.js <correo> <contraseña> <código de acceso>')
  process.exit(1)
}
if (password.length < 8) { console.error('Usa una contraseña de al menos 8 caracteres.'); process.exit(1) }

const [ph, ch] = await Promise.all([bcrypt.hash(password, 10), bcrypt.hash(code, 10)])
await pool.query(
  `INSERT INTO MB_DG_USUARIOS (email, password_hash, rol, codigo_acceso_hash) VALUES (?, ?, 'admin', ?)
   ON DUPLICATE KEY UPDATE password_hash = VALUES(password_hash), rol = 'admin', codigo_acceso_hash = VALUES(codigo_acceso_hash)`,
  [email.trim().toLowerCase(), ph, ch])
console.log(`Administrador listo: ${email.trim().toLowerCase()}`)
await pool.end()
