// Definición de las tablas del modelo y utilidades PURAS (sin base de datos) para el CRUD del panel admin.
// Todos los nombres de tabla/columna que llegan al SQL salen de este archivo, nunca del cliente.
import { HttpError } from './errores.js'

const T = (n, max, req = true) => ({ n, t: 'texto', max, req })
const N = (n, req = true, min = 0) => ({ n, t: 'entero', req, min })
const OP = (n, op, req = true, def) => ({ n, t: 'enum', op, req, ...(def !== undefined && { def }) })
const FK = (n, ref, req = true, tipo) => ({ n, t: 'fk', ref, req, ...(tipo && { tipo }) })
const HEX = n => ({ n, t: 'hex', req: true })
const BOOL = n => ({ n, t: 'bool', req: true, def: 1 })

export const TABLAS = {
  usuarios: {
    tabla: 'MB_DG_USUARIOS', titulo: 'Usuarios', labelSql: 'email', ro: ['creado_en'],
    cols: [
      T('email', 190), OP('rol', ['cliente', 'admin'], true, 'cliente'),
      { n: 'password', t: 'secreto', col: 'password_hash', req: true, min: 6 },
      { n: 'codigo_acceso', t: 'secreto', col: 'codigo_acceso_hash', req: false, min: 4 },
    ],
    // Un admin necesita código de acceso (regla ck_usuarios_admin de la base).
    validar: (body, modo) => {
      if (modo === 'crear' && body.rol === 'admin' && !String(body.codigo_acceso ?? '').trim())
        throw new HttpError(400, 'Un administrador necesita código de acceso.')
    },
  },
  autos: {
    tabla: 'MB_DG_AUTOS', titulo: 'Autos', labelSql: 'nombre',
    cols: [T('marca', 60), T('nombre', 100), OP('carroceria', ['gt', 'coupe', 'muscle', 'suv']), HEX('color_base'), BOOL('activo')],
  },
  colores: { tabla: 'MB_DG_COLORES', titulo: 'Colores de pintura', labelSql: 'nombre', cols: [T('nombre', 40), HEX('hex')] },
  acabados: { tabla: 'MB_DG_ACABADOS', titulo: 'Acabados de rin', labelSql: 'nombre', cols: [T('nombre', 40), HEX('hex')] },
  rines: {
    tabla: 'MB_DG_RINES', titulo: 'Rines', labelSql: 'nombre',
    cols: [T('nombre', 60), OP('estilo', ['five', 'mesh', 'turbine', 'multi']), HEX('acabado_base'), N('precio'), BOOL('activo')],
  },
  llantas: {
    tabla: 'MB_DG_LLANTAS', titulo: 'Llantas', labelSql: 'nombre',
    cols: [T('codigo', 10), T('nombre', 60), N('svg_radio', true, 1), N('svg_radio_rin', true, 1), N('precio'), BOOL('activo')],
  },
  medidas: {
    tabla: 'MB_DG_MEDIDAS', titulo: 'Medidas', labelSql: "CONCAT(tipo, ' ', etiqueta)",
    cols: [OP('tipo', ['rin', 'llanta']), T('etiqueta', 20), { n: 'factor', t: 'decimal', req: true }],
  },
  configuraciones: {
    tabla: 'MB_DG_CONFIGURACIONES', titulo: 'Configuraciones', labelSql: "CONCAT('#', id, ' ', nombre)", ro: ['creado_en'],
    cols: [
      OP('tipo', ['kit', 'rines', 'llantas']), T('nombre', 120), T('detalle', 255), N('precio_unitario'),
      FK('auto_id', 'autos', false), FK('color_id', 'colores', false), FK('rin_id', 'rines', false),
      FK('acabado_id', 'acabados', false), FK('medida_rin_id', 'medidas', false, 'rin'),
      OP('ancho_rin', ['7.5J', '8.5J', '9.5J'], false), FK('llanta_id', 'llantas', false),
      FK('medida_llanta_id', 'medidas', false, 'llanta'),
    ],
  },
  pedidos: {
    tabla: 'MB_DG_PEDIDOS', titulo: 'Pedidos', labelSql: 'codigo', ro: ['creado_en'],
    cols: [
      T('codigo', 20), FK('usuario_id', 'usuarios'), T('nombre_completo', 120), T('direccion', 200), T('ciudad', 80),
      T('departamento', 80), T('telefono', 30), N('subtotal'), { ...N('costo_envio'), def: 25000 }, N('total'),
      OP('estado', ['pendiente', 'pagado', 'enviado', 'entregado', 'cancelado'], true, 'pendiente'),
    ],
  },
  pedido_items: {
    tabla: 'MB_DG_PEDIDO_ITEMS', titulo: 'Renglones de pedido', labelSql: "CONCAT('#', id)",
    cols: [FK('pedido_id', 'pedidos'), FK('configuracion_id', 'configuraciones'), N('cantidad', true, 1)],
  },
  pagos: {
    tabla: 'MB_DG_PAGOS', titulo: 'Pagos', labelSql: "CONCAT('#', id)", ro: ['creado_en', 'actualizado_en'],
    cols: [
      FK('pedido_id', 'pedidos'), T('pasarela', 30), T('referencia_externa', 80, false),
      OP('estado', ['pendiente', 'aprobado', 'rechazado', 'reembolsado'], true, 'pendiente'), N('monto'),
      { ...T('moneda', 3), def: 'COP' }, OP('metodo_tipo', ['tarjeta', 'pse', 'nequi'], true, 'tarjeta'),
      T('marca', 20, false), T('ultimos4', 4, false),
    ],
  },
}

export const columnasVer = d => ['id', ...d.cols.filter(c => c.t !== 'secreto').map(c => c.n), ...(d.ro ?? [])]

// Lo que ve el navegador: describe los campos para armar los formularios (sin SQL).
export const esquemaPublico = () =>
  Object.entries(TABLAS).map(([clave, d]) => ({
    clave, titulo: d.titulo, ver: columnasVer(d),
    cols: d.cols.map(({ n, t, req, max, op, ref, tipo, min, def }) => ({ n, t, req, max, op, ref, tipo, min, def })),
  }))

const err = msg => new HttpError(400, msg)
const vacio = v => v === undefined || v === null || (typeof v === 'string' && v.trim() === '')

function convertir(c, raw) {
  const campo = c.n.replace(/_/g, ' ')
  if (c.t === 'bool') {
    if ([true, 1, '1', 'true'].includes(raw)) return 1
    if ([false, 0, '0', 'false'].includes(raw)) return 0
    throw err(`Valor no válido en ${campo}.`)
  }
  if (vacio(raw)) {
    if (c.req) throw err(`El campo ${campo} es obligatorio.`)
    return null
  }
  switch (c.t) {
    case 'texto': {
      const s = String(raw).trim()
      if (s.length > c.max) throw err(`${campo}: máximo ${c.max} caracteres.`)
      return s
    }
    case 'entero': case 'fk': {
      const n = Number(raw)
      if (!Number.isInteger(n)) throw err(`${campo}: debe ser un número entero.`)
      if (c.t === 'fk' ? n < 1 : n < (c.min ?? 0)) throw err(`${campo}: valor fuera de rango.`)
      if (n > 2147483647) throw err(`${campo}: valor demasiado grande.`)
      return n
    }
    case 'decimal': {
      const n = Number(raw)
      if (!Number.isFinite(n) || n <= 0 || n >= 100) throw err(`${campo}: debe estar entre 0.01 y 99.99.`)
      return Math.round(n * 100) / 100
    }
    case 'enum':
      if (!c.op.includes(raw)) throw err(`${campo}: opción no válida.`)
      return raw
    case 'hex':
      if (!/^#[0-9a-fA-F]{6}$/.test(String(raw))) throw err(`${campo}: usa el formato #rrggbb.`)
      return String(raw).toLowerCase()
    default:
      throw err(`Tipo de campo no soportado: ${c.n}.`)
  }
}

// Devuelve { columnaBD: valor }. `hash` convierte las contraseñas (nunca se guardan en claro).
// modo 'crear': exige los obligatorios y usa los valores por defecto. modo 'editar': solo toca lo enviado.
export function construirValores(d, body, modo, hash) {
  if (!body || typeof body !== 'object') throw err('Datos no válidos.')
  d.validar?.(body, modo)
  const out = {}
  for (const c of d.cols) {
    const raw = body[c.n]
    if (c.t === 'secreto') {
      const s = raw == null ? '' : String(raw)
      if (!s) { if (modo === 'crear' && c.req) throw err(`El campo ${c.n.replace(/_/g, ' ')} es obligatorio.`); continue }
      if (s.length < c.min || s.length > 72) throw err(`${c.n.replace(/_/g, ' ')}: entre ${c.min} y 72 caracteres.`)
      out[c.col] = hash(s)
      continue
    }
    if (raw === undefined) {
      if (modo === 'editar') continue
      if (c.def !== undefined) { out[c.n] = c.def; continue }
    }
    out[c.n] = convertir(c, raw)
  }
  return out
}

export function sqlInsertar(d, valores) {
  const cols = Object.keys(valores)
  if (!cols.length) throw err('No hay datos para guardar.')
  return { sql: `INSERT INTO ${d.tabla} (${cols.map(c => `\`${c}\``).join(', ')}) VALUES (${cols.map(() => '?').join(', ')})`, params: Object.values(valores) }
}

export function sqlActualizar(d, valores, id) {
  const cols = Object.keys(valores)
  if (!cols.length) throw err('No hay cambios para guardar.')
  return { sql: `UPDATE ${d.tabla} SET ${cols.map(c => `\`${c}\` = ?`).join(', ')} WHERE id = ?`, params: [...Object.values(valores), id] }
}

// Traduce errores de MySQL/MariaDB a mensajes entendibles. null = error desconocido (se registra y sale 500).
export function errorAmigable(e) {
  const cod = e?.code, no = e?.errno
  if (cod === 'ER_DUP_ENTRY') return { status: 409, message: 'Ya existe un registro con ese valor único (correo, código, nombre, hex...).' }
  if (cod === 'ER_ROW_IS_REFERENCED_2' || cod === 'ER_ROW_IS_REFERENCED')
    return { status: 409, message: 'No se puede eliminar: otros registros dependen de este (por ejemplo un pedido con pagos).' }
  if (cod === 'ER_NO_REFERENCED_ROW_2' || cod === 'ER_NO_REFERENCED_ROW')
    return { status: 400, message: 'Uno de los registros relacionados (llave foránea) no existe.' }
  if (cod === 'ER_CHECK_CONSTRAINT_VIOLATED' || no === 3819 || no === 4025)
    return { status: 400, message: 'Los datos no cumplen una regla de la tabla (por ejemplo: total = subtotal + envío, o el admin necesita código).' }
  if (cod === 'ER_DATA_TOO_LONG' || cod === 'ER_TRUNCATED_WRONG_VALUE' || cod === 'ER_WARN_DATA_OUT_OF_RANGE' || cod === 'ER_BAD_NULL_ERROR')
    return { status: 400, message: 'Hay un dato con formato, tamaño o valor no válido.' }
  return null
}

// Filtros del reporte de auditoría. Devuelve { where, params } listos para el SQL.
export function filtrosAuditoria(q = {}) {
  const where = [], params = []
  const fecha = (v, nombre) => {
    if (vacio(v)) return null
    if (!/^\d{4}-\d{2}-\d{2}$/.test(String(v)) || Number.isNaN(Date.parse(v))) throw err(`Fecha "${nombre}" no válida (usa AAAA-MM-DD).`)
    return String(v)
  }
  const desde = fecha(q.desde, 'desde'), hasta = fecha(q.hasta, 'hasta')
  if (desde && hasta && desde > hasta) throw err('La fecha "desde" no puede ser posterior a "hasta".')
  if (desde) { where.push('a.fecha >= ?'); params.push(desde) }
  if (hasta) { where.push('a.fecha < DATE_ADD(?, INTERVAL 1 DAY)'); params.push(hasta) }
  if (!vacio(q.tabla)) {
    if (!/^MB_DG_[A-Z_]{1,30}$/.test(String(q.tabla))) throw err('Tabla no válida.')
    where.push('a.tabla = ?'); params.push(String(q.tabla))
  }
  if (!vacio(q.operacion)) {
    if (!['INSERT', 'UPDATE', 'DELETE'].includes(q.operacion)) throw err('Operación no válida.')
    where.push('a.operacion = ?'); params.push(q.operacion)
  }
  return { where: where.length ? 'WHERE ' + where.join(' AND ') : '', params }
}
