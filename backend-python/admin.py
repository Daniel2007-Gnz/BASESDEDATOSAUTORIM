import re
from datetime import date
from decimal import Decimal
from flask import Blueprint, g, jsonify, request
from auth import autenticar, hash_pw
from crud import TABLAS, columnas_ver, construir_valores, error_amigable, esquema_publico, filtros_auditoria, sql_actualizar, sql_insertar
from db import consultar, run, transaccion
from errores import HttpError, cuerpo

bp = Blueprint('admin', __name__, url_prefix='/api/admin')


@bp.before_request
def _auth():
    if request.method != 'OPTIONS':
        autenticar('admin')


def tabla_de(clave):
    d = TABLAS.get(clave)
    if not d:
        raise HttpError(404, 'Tabla no encontrada.')
    return d


def id_de(v):
    if not re.fullmatch(r'[0-9]+', v) or int(v) < 1:
        raise HttpError(400, 'Id no válido.')
    return int(v)


def traducir(e):
    if isinstance(e, HttpError):
        return e
    m = error_amigable(e)
    return HttpError(m['status'], m['message']) if m else e


def entero(v, defecto):
    try:
        return int(v)
    except (TypeError, ValueError):
        return defecto


@bp.get('/resumen')
def resumen():
    return jsonify((consultar('SELECT pedidos, clientes FROM MB_DG_V_RESUMEN_ADMIN') or [{}])[0])


@bp.get('/pedidos')
def pedidos():
    return jsonify(consultar('SELECT pedido, fecha, cliente, productos, total, estado FROM MB_DG_V_PEDIDOS_ADMIN ORDER BY fecha DESC'))


@bp.get('/tablas')
def tablas():
    return jsonify(esquema_publico())


@bp.get('/tablas/<clave>/opciones')
def opciones(clave):
    d = tabla_de(clave)
    t = request.args.get('tipo')
    tipo = t if t in ('rin', 'llanta') and any(c['n'] == 'tipo' for c in d['cols']) else None
    return jsonify(consultar(
        f"SELECT id, {d['labelSql']} AS label FROM {d['tabla']} {'WHERE tipo = ?' if tipo else ''} ORDER BY id LIMIT 1000", [tipo] if tipo else []))


@bp.get('/tablas/<clave>')
def listar(clave):
    d = tabla_de(clave)
    por_pagina = 20
    pagina = max(1, entero(request.args.get('pagina'), 1))
    q = request.args.get('q', '').strip()[:100]
    where = f"WHERE {d['labelSql']} LIKE ?" if q else ''
    params = [f'%{q}%'] if q else []
    total = consultar(f"SELECT COUNT(*) AS total FROM {d['tabla']} {where}", params)[0]['total']
    filas = consultar(
        f"SELECT {', '.join(f'`{c}`' for c in columnas_ver(d))} FROM {d['tabla']} {where} ORDER BY id DESC LIMIT ? OFFSET ?",
        [*params, por_pagina, (pagina - 1) * por_pagina])
    return jsonify(filas=filas, total=total, pagina=pagina, paginas=max(1, -(-total // por_pagina)))


@bp.post('/tablas/<clave>')
def crear(clave):
    d = tabla_de(clave)
    sql, params = sql_insertar(d, construir_valores(d, cuerpo(), 'crear', hash_pw))
    try:
        nuevo = transaccion(g.user['id'], lambda c: run(c, sql, params).lastrowid)
    except Exception as e:
        raise traducir(e)
    return jsonify(id=nuevo), 201


@bp.put('/tablas/<clave>/<id>')
def editar(clave, id):
    d, id = tabla_de(clave), id_de(id)
    sql, params = sql_actualizar(d, construir_valores(d, cuerpo(), 'editar', hash_pw), id)
    try:
        n = transaccion(g.user['id'], lambda c: run(c, sql, params).rowcount)
    except Exception as e:
        raise traducir(e)
    if not n:
        raise HttpError(404, 'Registro no encontrado.')
    return jsonify(ok=True)


@bp.delete('/tablas/<clave>/<id>')
def eliminar(clave, id):
    d, id = tabla_de(clave), id_de(id)
    if clave == 'usuarios' and id == g.user['id']:
        raise HttpError(400, 'No puedes eliminar tu propio usuario.')
    try:
        n = transaccion(g.user['id'], lambda c: run(c, f"DELETE FROM {d['tabla']} WHERE id = ?", [id]).rowcount)
    except Exception as e:
        raise traducir(e)
    if not n:
        raise HttpError(404, 'Registro no encontrado.')
    return jsonify(ok=True)


@bp.get('/auditoria')
def auditoria():
    where, params = filtros_auditoria(request.args)
    todo = request.args.get('todo') == '1'
    por_pagina = 5000 if todo else 50
    pagina = 1 if todo else max(1, entero(request.args.get('pagina'), 1))
    total = consultar(f'SELECT COUNT(*) AS total FROM MB_DG_AUDITORIA a {where}', params)[0]['total']
    resumen = consultar(
        f"""SELECT DATE_FORMAT(a.fecha, '%Y-%m-%d') AS dia, COUNT(*) AS total,
                   SUM(a.operacion = 'INSERT') AS inserts, SUM(a.operacion = 'UPDATE') AS updates, SUM(a.operacion = 'DELETE') AS deletes
            FROM MB_DG_AUDITORIA a {where} GROUP BY dia ORDER BY dia DESC LIMIT 366""", params)
    filas = consultar(
        f"""SELECT a.id, DATE_FORMAT(a.fecha, '%Y-%m-%d %H:%i:%s') AS fecha, a.tabla, a.operacion, a.registro_id,
                   a.usuario_app, u.email AS usuario_email, a.usuario_bd, a.datos_anteriores, a.datos_nuevos
            FROM MB_DG_AUDITORIA a LEFT JOIN MB_DG_USUARIOS u ON u.id = a.usuario_app
            {where} ORDER BY a.id DESC LIMIT ? OFFSET ?""", [*params, por_pagina, (pagina - 1) * por_pagina])
    tablas = consultar('SELECT DISTINCT tabla FROM MB_DG_AUDITORIA ORDER BY tabla')
    return jsonify(
        total=total, pagina=pagina, paginas=max(1, -(-total // por_pagina)), tablas=[t['tabla'] for t in tablas],
        resumen=[{'dia': x['dia'], **{k: int(x[k]) for k in ('total', 'inserts', 'updates', 'deletes')}} for x in resumen],
        filas=filas)


VENDIDO = "p.estado IN ('pagado','enviado','entregado')"
DETALLE = f"""FROM MB_DG_PEDIDOS p JOIN MB_DG_PEDIDO_ITEMS i ON i.pedido_id = p.id JOIN MB_DG_CONFIGURACIONES c ON c.id = i.configuracion_id
              WHERE {VENDIDO} AND YEAR(p.creado_en) = ?"""


def num(o):
    return {k: int(v) if isinstance(v, Decimal) else v for k, v in o.items()}


@bp.get('/estadisticas')
def estadisticas():
    anio = entero(request.args.get('anio'), 0) or date.today().year
    if not 2000 <= anio <= 2100:
        raise HttpError(400, 'Año no válido.')
    u = consultar("SELECT COALESCE(SUM(rol = 'cliente'), 0) AS clientes, COALESCE(SUM(rol = 'admin'), 0) AS administradores FROM MB_DG_USUARIOS")[0]
    b = consultar(f'SELECT COUNT(DISTINCT p.usuario_id) AS compradores, COUNT(*) AS pedidos FROM MB_DG_PEDIDOS p WHERE {VENDIDO}')[0]
    t = consultar(f'SELECT COALESCE(SUM(i.cantidad), 0) AS unidades, COALESCE(SUM(i.cantidad * c.precio_unitario), 0) AS ingresos {DETALLE}', [anio])[0]
    u, t = num(u), num(t)
    return jsonify(
        anio=anio,
        anios=[x['anio'] for x in consultar('SELECT DISTINCT YEAR(creado_en) AS anio FROM MB_DG_PEDIDOS ORDER BY anio DESC')],
        usuarios={**u, 'compradores': b['compradores'], 'sin_compras': u['clientes'] - min(b['compradores'], u['clientes'])},
        admins=consultar("SELECT id, email, DATE_FORMAT(creado_en, '%Y-%m-%d') AS creado FROM MB_DG_USUARIOS WHERE rol = 'admin' ORDER BY id"),
        totales={'pedidos': b['pedidos'], **t},
        mensual=[num(x) for x in consultar(
            f"""SELECT DATE_FORMAT(p.creado_en, '%Y-%m') AS mes, COUNT(DISTINCT p.id) AS pedidos, COUNT(DISTINCT p.usuario_id) AS compradores,
                       SUM(i.cantidad) AS unidades, SUM(i.cantidad * c.precio_unitario) AS ingresos {DETALLE} GROUP BY mes ORDER BY mes""", [anio])],
        productos=[num(x) for x in consultar(
            f"""SELECT DATE_FORMAT(p.creado_en, '%Y-%m') AS mes, c.tipo, c.nombre AS producto,
                       SUM(i.cantidad) AS unidades, SUM(i.cantidad * c.precio_unitario) AS ingresos {DETALLE} GROUP BY mes, c.tipo, c.nombre ORDER BY mes, unidades DESC""", [anio])])
