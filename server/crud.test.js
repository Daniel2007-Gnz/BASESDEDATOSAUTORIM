import test from 'node:test'
import assert from 'node:assert/strict'
import { TABLAS, construirValores, sqlInsertar, sqlActualizar, errorAmigable, filtrosAuditoria, esquemaPublico, columnasVer } from './crud.js'

const hash = s => `hash(${s})`
const falla = (fn, texto) => assert.throws(fn, e => e.status === 400 && (!texto || e.message.includes(texto)))

test('crear auto válido: normaliza hex y aplica activo por defecto', () => {
  const v = construirValores(TABLAS.autos, { marca: ' Vektra ', nombre: 'Nova', carroceria: 'gt', color_base: '#C81E3A' }, 'crear', hash)
  assert.deepEqual(v, { marca: 'Vektra', nombre: 'Nova', carroceria: 'gt', color_base: '#c81e3a', activo: 1 })
})
test('campos obligatorios, enum, hex y largo se validan', () => {
  falla(() => construirValores(TABLAS.autos, { marca: '', nombre: 'x', carroceria: 'gt', color_base: '#000000' }, 'crear', hash), 'obligatorio')
  falla(() => construirValores(TABLAS.autos, { marca: 'a', nombre: 'x', carroceria: 'camion', color_base: '#000000' }, 'crear', hash), 'opción')
  falla(() => construirValores(TABLAS.autos, { marca: 'a', nombre: 'x', carroceria: 'gt', color_base: 'rojo' }, 'crear', hash), '#rrggbb')
  falla(() => construirValores(TABLAS.autos, { marca: 'a'.repeat(61), nombre: 'x', carroceria: 'gt', color_base: '#000000' }, 'crear', hash), 'máximo')
})
test('enteros: rechaza decimales, negativos y texto', () => {
  const base = { nombre: 'R', estilo: 'five', acabado_base: '#c9ccd1' }
  falla(() => construirValores(TABLAS.rines, { ...base, precio: '12.5' }, 'crear', hash))
  falla(() => construirValores(TABLAS.rines, { ...base, precio: -1 }, 'crear', hash))
  falla(() => construirValores(TABLAS.rines, { ...base, precio: 'abc' }, 'crear', hash))
  assert.equal(construirValores(TABLAS.rines, { ...base, precio: '1890000' }, 'crear', hash).precio, 1890000)
})
test('editar solo toca lo enviado; vacío en nullable -> NULL', () => {
  assert.deepEqual(construirValores(TABLAS.rines, { precio: 2000000 }, 'editar', hash), { precio: 2000000 })
  const v = construirValores(TABLAS.configuraciones, { auto_id: '', ancho_rin: '' }, 'editar', hash)
  assert.deepEqual(v, { auto_id: null, ancho_rin: null })
})
test('usuarios: contraseña y código se hashean, nunca van en claro', () => {
  const v = construirValores(TABLAS.usuarios, { email: 'a@b.co', rol: 'admin', password: 'secreta1', codigo_acceso: 'AR-1' }, 'crear', hash)
  assert.equal(v.password_hash, 'hash(secreta1)')
  assert.equal(v.codigo_acceso_hash, 'hash(AR-1)')
  assert.ok(!('password' in v) && !('codigo_acceso' in v))
  falla(() => construirValores(TABLAS.usuarios, { email: 'a@b.co', rol: 'admin', password: 'secreta1' }, 'crear', hash), 'código de acceso')
  falla(() => construirValores(TABLAS.usuarios, { email: 'a@b.co', rol: 'cliente', password: '123' }, 'crear', hash), 'entre 6')
  // al editar, contraseña vacía = no cambiarla
  assert.deepEqual(construirValores(TABLAS.usuarios, { email: 'n@b.co', password: '' }, 'editar', hash), { email: 'n@b.co' })
})
test('medidas.factor: DECIMAL(4,2)', () => {
  const b = { tipo: 'rin', etiqueta: '23"' }
  assert.equal(construirValores(TABLAS.medidas, { ...b, factor: '1.456' }, 'crear', hash).factor, 1.46)
  falla(() => construirValores(TABLAS.medidas, { ...b, factor: 100 }, 'crear', hash))
  falla(() => construirValores(TABLAS.medidas, { ...b, factor: 0 }, 'crear', hash))
})
test('pedidos: costo_envio y estado usan su valor por defecto al crear', () => {
  const v = construirValores(TABLAS.pedidos, { codigo: 'AR-111111', usuario_id: 1, nombre_completo: 'N', direccion: 'D', ciudad: 'C', departamento: 'D', telefono: '1', subtotal: 10, total: 25010 }, 'crear', hash)
  assert.equal(v.costo_envio, 25000)
  assert.equal(v.estado, 'pendiente')
})
test('SQL: identificadores salen de la definición, valores van como parámetros', () => {
  const ins = sqlInsertar(TABLAS.colores, { nombre: "x'); DROP TABLE y;--", hex: '#000000' })
  assert.equal(ins.sql, 'INSERT INTO MB_DG_COLORES (`nombre`, `hex`) VALUES (?, ?)')
  assert.deepEqual(ins.params, ["x'); DROP TABLE y;--", '#000000'])
  const upd = sqlActualizar(TABLAS.colores, { nombre: 'n' }, 7)
  assert.equal(upd.sql, 'UPDATE MB_DG_COLORES SET `nombre` = ? WHERE id = ?')
  assert.deepEqual(upd.params, ['n', 7])
  falla(() => sqlActualizar(TABLAS.colores, {}, 1))
})
test('el listado nunca incluye hashes; el esquema público no trae SQL', () => {
  assert.deepEqual(columnasVer(TABLAS.usuarios), ['id', 'email', 'rol', 'creado_en'])
  assert.ok(!JSON.stringify(esquemaPublico()).includes('password_hash'))
  assert.ok(!JSON.stringify(esquemaPublico()).includes('MB_DG_'))
})
test('toda llave foránea apunta a una tabla definida', () => {
  for (const d of Object.values(TABLAS)) for (const c of d.cols) if (c.t === 'fk') assert.ok(TABLAS[c.ref], `${d.tabla}.${c.n}`)
})
test('errores de MySQL se traducen', () => {
  assert.equal(errorAmigable({ code: 'ER_DUP_ENTRY' }).status, 409)
  assert.equal(errorAmigable({ code: 'ER_ROW_IS_REFERENCED_2' }).status, 409)
  assert.equal(errorAmigable({ code: 'ER_NO_REFERENCED_ROW_2' }).status, 400)
  assert.equal(errorAmigable({ errno: 4025 }).status, 400)
  assert.equal(errorAmigable({ errno: 3819 }).status, 400)
  assert.equal(errorAmigable(new Error('otro')), null)
})
test('filtros de auditoría', () => {
  assert.deepEqual(filtrosAuditoria({}), { where: '', params: [] })
  const f = filtrosAuditoria({ desde: '2026-11-01', hasta: '2026-11-19', tabla: 'MB_DG_PEDIDOS', operacion: 'UPDATE' })
  assert.equal(f.where, 'WHERE a.fecha >= ? AND a.fecha < DATE_ADD(?, INTERVAL 1 DAY) AND a.tabla = ? AND a.operacion = ?')
  assert.deepEqual(f.params, ['2026-11-01', '2026-11-19', 'MB_DG_PEDIDOS', 'UPDATE'])
  falla(() => filtrosAuditoria({ desde: '2026-13-45' }), 'no válida')
  falla(() => filtrosAuditoria({ desde: '1; DROP' }), 'no válida')
  falla(() => filtrosAuditoria({ desde: '2026-11-20', hasta: '2026-11-01' }), 'posterior')
  falla(() => filtrosAuditoria({ tabla: "x' OR 1=1" }), 'Tabla')
  falla(() => filtrosAuditoria({ operacion: 'DROP' }), 'Operación')
})
