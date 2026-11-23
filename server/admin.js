import { Router } from 'express'
import bcrypt from 'bcryptjs'
import { pool, transaccion } from './db.js'
import { HttpError } from './errores.js'
import { requiere } from './auth.js'
import { TABLAS, columnasVer, esquemaPublico, construirValores, sqlInsertar, sqlActualizar, errorAmigable, filtrosAuditoria } from './crud.js'

const r = Router()
r.use(requiere('admin'))

const ah = fn => (req, res, next) => fn(req, res, next).catch(next)
const tablaDe = req => {
  const d = Object.hasOwn(TABLAS, req.params.clave) ? TABLAS[req.params.clave] : null
  if (!d) throw new HttpError(404, 'Tabla no encontrada.')
  return d
}
const idDe = req => {
  const id = Number(req.params.id)
  if (!Number.isInteger(id) || id < 1) throw new HttpError(400, 'Id no válido.')
  return id
}
// Errores de MySQL conocidos -> mensaje claro; los demás siguen como error 500 (se registran en consola).
const traducir = e => {
  const m = !(e instanceof HttpError) && errorAmigable(e)
  return m ? new HttpError(m.status, m.message) : e
}
const hash = s => bcrypt.hashSync(s, 10)

// ---------------------------------------------------------------- CRUD genérico
r.get('/tablas', (_req, res) => res.json(esquemaPublico()))

// Opciones (id + texto) para llenar las listas de llaves foráneas.
r.get('/tablas/:clave/opciones', ah(async (req, res) => {
  const d = tablaDe(req)
  const tipo = ['rin', 'llanta'].includes(req.query.tipo) && d.cols.some(c => c.n === 'tipo') ? req.query.tipo : null
  const [rows] = await pool.query(
    `SELECT id, ${d.labelSql} AS label FROM ${d.tabla} ${tipo ? 'WHERE tipo = ?' : ''} ORDER BY id LIMIT 1000`, tipo ? [tipo] : [])
  res.json(rows)
}))

r.get('/tablas/:clave', ah(async (req, res) => {
  const d = tablaDe(req)
  const POR_PAGINA = 20
  const pagina = Math.max(1, parseInt(req.query.pagina) || 1)
  const q = String(req.query.q ?? '').trim().slice(0, 100)
  const where = q ? `WHERE ${d.labelSql} LIKE ?` : ''
  const params = q ? [`%${q}%`] : []
  const [[{ total }]] = await pool.query(`SELECT COUNT(*) AS total FROM ${d.tabla} ${where}`, params)
  const [filas] = await pool.query(
    `SELECT ${columnasVer(d).map(c => `\`${c}\``).join(', ')} FROM ${d.tabla} ${where} ORDER BY id DESC LIMIT ? OFFSET ?`,
    [...params, POR_PAGINA, (pagina - 1) * POR_PAGINA])
  res.json({ filas, total, pagina, paginas: Math.max(1, Math.ceil(total / POR_PAGINA)) })
}))

// Todas las escrituras van en transacción con @app_usuario_id: los triggers anotan en la auditoría QUIÉN lo hizo.
r.post('/tablas/:clave', ah(async (req, res) => {
  const d = tablaDe(req)
  const { sql, params } = sqlInsertar(d, construirValores(d, req.body, 'crear', hash))
  try {
    const [out] = await transaccion(req.user.id, conn => conn.query(sql, params))
    res.status(201).json({ id: out.insertId })
  } catch (e) { throw traducir(e) }
}))

r.put('/tablas/:clave/:id', ah(async (req, res) => {
  const d = tablaDe(req), id = idDe(req)
  const { sql, params } = sqlActualizar(d, construirValores(d, req.body, 'editar', hash), id)
  try {
    const [out] = await transaccion(req.user.id, conn => conn.query(sql, params))
    if (!out.affectedRows) throw new HttpError(404, 'Registro no encontrado.')
    res.json({ ok: true })
  } catch (e) { throw traducir(e) }
}))

r.delete('/tablas/:clave/:id', ah(async (req, res) => {
  const d = tablaDe(req), id = idDe(req)
  if (req.params.clave === 'usuarios' && id === req.user.id) throw new HttpError(400, 'No puedes eliminar tu propio usuario.')
  try {
    const [out] = await transaccion(req.user.id, conn => conn.query(`DELETE FROM ${d.tabla} WHERE id = ?`, [id]))
    if (!out.affectedRows) throw new HttpError(404, 'Registro no encontrado.')
    res.json({ ok: true })
  } catch (e) { throw traducir(e) }
}))

// ---------------------------------------------------------------- Reporte de auditoría
// Filtros: desde, hasta (AAAA-MM-DD, ambos inclusivos), tabla, operacion. todo=1 devuelve hasta 5000 filas (para CSV).
r.get('/auditoria', ah(async (req, res) => {
  const { where, params } = filtrosAuditoria(req.query)
  const todo = req.query.todo === '1'
  const POR_PAGINA = todo ? 5000 : 50
  const pagina = todo ? 1 : Math.max(1, parseInt(req.query.pagina) || 1)

  const [[{ total }]] = await pool.query(`SELECT COUNT(*) AS total FROM MB_DG_AUDITORIA a ${where}`, params)
  const [resumen] = await pool.query(
    `SELECT DATE_FORMAT(a.fecha, '%Y-%m-%d') AS dia, COUNT(*) AS total,
            SUM(a.operacion = 'INSERT') AS inserts, SUM(a.operacion = 'UPDATE') AS updates, SUM(a.operacion = 'DELETE') AS deletes
     FROM MB_DG_AUDITORIA a ${where} GROUP BY dia ORDER BY dia DESC LIMIT 366`, params)
  const [filas] = await pool.query(
    `SELECT a.id, DATE_FORMAT(a.fecha, '%Y-%m-%d %H:%i:%s') AS fecha, a.tabla, a.operacion, a.registro_id,
            a.usuario_app, u.email AS usuario_email, a.usuario_bd, a.datos_anteriores, a.datos_nuevos
     FROM MB_DG_AUDITORIA a LEFT JOIN MB_DG_USUARIOS u ON u.id = a.usuario_app
     ${where} ORDER BY a.id DESC LIMIT ? OFFSET ?`,
    [...params, POR_PAGINA, (pagina - 1) * POR_PAGINA])
  const [tablas] = await pool.query('SELECT DISTINCT tabla FROM MB_DG_AUDITORIA ORDER BY tabla')

  res.json({
    total, pagina, paginas: Math.max(1, Math.ceil(total / POR_PAGINA)), tablas: tablas.map(t => t.tabla),
    resumen: resumen.map(x => ({ dia: x.dia, total: Number(x.total), inserts: Number(x.inserts), updates: Number(x.updates), deletes: Number(x.deletes) })),
    filas,
  })
}))

// ---------------------------------------------------------------- Estadísticas
const VENDIDO = "p.estado IN ('pagado','enviado','entregado')"
const NUMS = ['clientes', 'administradores', 'compradores', 'pedidos', 'unidades', 'ingresos']
const num = o => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, NUMS.includes(k) ? Number(v) : v]))
const DETALLE = `FROM MB_DG_PEDIDOS p JOIN MB_DG_PEDIDO_ITEMS i ON i.pedido_id = p.id JOIN MB_DG_CONFIGURACIONES c ON c.id = i.configuracion_id
                 WHERE ${VENDIDO} AND YEAR(p.creado_en) = ?`

r.get('/estadisticas', ah(async (req, res) => {
  const anio = parseInt(req.query.anio) || new Date().getFullYear()
  if (anio < 2000 || anio > 2100) throw new HttpError(400, 'Año no válido.')
  const q = async (sql, params = []) => (await pool.query(sql, params))[0]
  const [u] = await q("SELECT COALESCE(SUM(rol = 'cliente'), 0) AS clientes, COALESCE(SUM(rol = 'admin'), 0) AS administradores FROM MB_DG_USUARIOS")
  const [b] = await q(`SELECT COUNT(DISTINCT p.usuario_id) AS compradores, COUNT(*) AS pedidos FROM MB_DG_PEDIDOS p WHERE ${VENDIDO}`)
  const [t] = await q(`SELECT COALESCE(SUM(i.cantidad), 0) AS unidades, COALESCE(SUM(i.cantidad * c.precio_unitario), 0) AS ingresos ${DETALLE}`, [anio])
  res.json({
    anio,
    anios: (await q('SELECT DISTINCT YEAR(creado_en) AS anio FROM MB_DG_PEDIDOS ORDER BY anio DESC')).map(x => x.anio),
    usuarios: num({ ...u, compradores: b.compradores, sin_compras: Number(u.clientes) - Math.min(Number(b.compradores), Number(u.clientes)) }),
    admins: await q("SELECT id, email, DATE_FORMAT(creado_en, '%Y-%m-%d') AS creado FROM MB_DG_USUARIOS WHERE rol = 'admin' ORDER BY id"),
    totales: num({ pedidos: b.pedidos, ...t }),
    mensual: (await q(`SELECT DATE_FORMAT(p.creado_en, '%Y-%m') AS mes, COUNT(DISTINCT p.id) AS pedidos, COUNT(DISTINCT p.usuario_id) AS compradores,
                              SUM(i.cantidad) AS unidades, SUM(i.cantidad * c.precio_unitario) AS ingresos ${DETALLE} GROUP BY mes ORDER BY mes`, [anio])).map(num),
    productos: (await q(`SELECT DATE_FORMAT(p.creado_en, '%Y-%m') AS mes, c.tipo, c.nombre AS producto,
                                SUM(i.cantidad) AS unidades, SUM(i.cantidad * c.precio_unitario) AS ingresos ${DETALLE} GROUP BY mes, c.tipo, c.nombre ORDER BY mes, unidades DESC`, [anio])).map(num),
  })
}))

export default r
