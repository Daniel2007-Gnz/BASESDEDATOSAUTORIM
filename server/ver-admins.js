// Lista los administradores que ya existen en la base de datos (nunca muestra hashes).
//   npm run ver-admins
import 'dotenv/config'
import { pool } from './db.js'

const [rows] = await pool.query(
  "SELECT id, email, (codigo_acceso_hash IS NOT NULL) AS tiene_codigo FROM MB_DG_USUARIOS WHERE rol = 'admin' ORDER BY id")
if (!rows.length) {
  console.log('No hay administradores. Crea uno con:\n  npm run crear-admin -- correo@dominio.com "TuClaveSegura1" "TU-CODIGO"')
} else {
  console.log('Administradores en la base de datos:')
  for (const r of rows) console.log(`  #${r.id}  ${r.email}  (código de acceso: ${r.tiene_codigo ? 'sí' : 'NO, vuelve a correr crear-admin'})`)
  console.log('\nLas contraseñas y códigos están cifrados y no se pueden leer. Para cambiarlos: npm run crear-admin -- <correo> "<nueva clave>" "<nuevo código>"')
}
await pool.end()
