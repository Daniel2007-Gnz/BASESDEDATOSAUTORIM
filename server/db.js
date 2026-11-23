import mysql from 'mysql2/promise'

const uri = process.env.DATABASE_URL?.replace(/^mysql\+\w+:/, 'mysql:')
export const pool = mysql.createPool({
  ...(uri ? { uri } : {
    host: process.env.DB_HOST || '127.0.0.1',
    port: Number(process.env.DB_PORT) || 3306,
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD ?? '',
    database: process.env.DB_NAME || 'autorim',
  }),
  charset: 'utf8mb4',
  waitForConnections: true,
  connectionLimit: 10,
})

// Ejecuta fn(conn) dentro de una transacción. Informa a los triggers de auditoría
// quién hizo el cambio (SET @app_usuario_id) y lo limpia antes de devolver la conexión al pool.
export async function transaccion(usuarioId, fn) {
  const conn = await pool.getConnection()
  try {
    await conn.beginTransaction()
    await conn.query('SET @app_usuario_id = ?', [usuarioId ?? null])
    const result = await fn(conn)
    await conn.commit()
    return result
  } catch (e) {
    await conn.rollback().catch(() => {})
    throw e
  } finally {
    await conn.query('SET @app_usuario_id = NULL').catch(() => {})
    conn.release()
  }
}
