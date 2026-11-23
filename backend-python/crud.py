import math
import re
from datetime import datetime
from errores import HttpError, errno_de


def T(n, mx, req=True): return {'n': n, 't': 'texto', 'max': mx, 'req': req}
def N(n, req=True, mn=0): return {'n': n, 't': 'entero', 'req': req, 'min': mn}
def HEX(n): return {'n': n, 't': 'hex', 'req': True}
def BOOL(n): return {'n': n, 't': 'bool', 'req': True, 'def': 1}


def OP(n, op, req=True, *d):
    return {'n': n, 't': 'enum', 'op': op, 'req': req, **({'def': d[0]} if d else {})}


def FK(n, ref, req=True, tipo=None):
    return {'n': n, 't': 'fk', 'ref': ref, 'req': req, **({'tipo': tipo} if tipo else {})}


def _validar_usuario(body, modo):
    if modo == 'crear' and body.get('rol') == 'admin' and not str(body.get('codigo_acceso') or '').strip():
        raise HttpError(400, 'Un administrador necesita código de acceso.')


TABLAS = {
    'usuarios': {
        'tabla': 'MB_DG_USUARIOS', 'titulo': 'Usuarios', 'labelSql': 'email', 'ro': ['creado_en'],
        'cols': [
            T('email', 190), OP('rol', ['cliente', 'admin'], True, 'cliente'),
            {'n': 'password', 't': 'secreto', 'col': 'password_hash', 'req': True, 'min': 6},
            {'n': 'codigo_acceso', 't': 'secreto', 'col': 'codigo_acceso_hash', 'req': False, 'min': 4},
        ],
        'validar': _validar_usuario,
    },
    'autos': {
        'tabla': 'MB_DG_AUTOS', 'titulo': 'Autos', 'labelSql': 'nombre',
        'cols': [T('marca', 60), T('nombre', 100), OP('carroceria', ['gt', 'coupe', 'muscle', 'suv']), HEX('color_base'), BOOL('activo')],
    },
    'colores': {'tabla': 'MB_DG_COLORES', 'titulo': 'Colores de pintura', 'labelSql': 'nombre', 'cols': [T('nombre', 40), HEX('hex')]},
    'acabados': {'tabla': 'MB_DG_ACABADOS', 'titulo': 'Acabados de rin', 'labelSql': 'nombre', 'cols': [T('nombre', 40), HEX('hex')]},
    'rines': {
        'tabla': 'MB_DG_RINES', 'titulo': 'Rines', 'labelSql': 'nombre',
        'cols': [T('nombre', 60), OP('estilo', ['five', 'mesh', 'turbine', 'multi']), HEX('acabado_base'), N('precio'), BOOL('activo')],
    },
    'llantas': {
        'tabla': 'MB_DG_LLANTAS', 'titulo': 'Llantas', 'labelSql': 'nombre',
        'cols': [T('codigo', 10), T('nombre', 60), N('svg_radio', True, 1), N('svg_radio_rin', True, 1), N('precio'), BOOL('activo')],
    },
    'medidas': {
        'tabla': 'MB_DG_MEDIDAS', 'titulo': 'Medidas', 'labelSql': "CONCAT(tipo, ' ', etiqueta)",
        'cols': [OP('tipo', ['rin', 'llanta']), T('etiqueta', 20), {'n': 'factor', 't': 'decimal', 'req': True}],
    },
    'configuraciones': {
        'tabla': 'MB_DG_CONFIGURACIONES', 'titulo': 'Configuraciones', 'labelSql': "CONCAT('#', id, ' ', nombre)", 'ro': ['creado_en'],
        'cols': [
            OP('tipo', ['kit', 'rines', 'llantas']), T('nombre', 120), T('detalle', 255), N('precio_unitario'),
            FK('auto_id', 'autos', False), FK('color_id', 'colores', False), FK('rin_id', 'rines', False),
            FK('acabado_id', 'acabados', False), FK('medida_rin_id', 'medidas', False, 'rin'),
            OP('ancho_rin', ['7.5J', '8.5J', '9.5J'], False), FK('llanta_id', 'llantas', False),
            FK('medida_llanta_id', 'medidas', False, 'llanta'),
        ],
    },
    'pedidos': {
        'tabla': 'MB_DG_PEDIDOS', 'titulo': 'Pedidos', 'labelSql': 'codigo', 'ro': ['creado_en'],
        'cols': [
            T('codigo', 20), FK('usuario_id', 'usuarios'), T('nombre_completo', 120), T('direccion', 200), T('ciudad', 80),
            T('departamento', 80), T('telefono', 30), N('subtotal'), {**N('costo_envio'), 'def': 25000}, N('total'),
            OP('estado', ['pendiente', 'pagado', 'enviado', 'entregado', 'cancelado'], True, 'pendiente'),
        ],
    },
    'pedido_items': {
        'tabla': 'MB_DG_PEDIDO_ITEMS', 'titulo': 'Renglones de pedido', 'labelSql': "CONCAT('#', id)",
        'cols': [FK('pedido_id', 'pedidos'), FK('configuracion_id', 'configuraciones'), N('cantidad', True, 1)],
    },
    'pagos': {
        'tabla': 'MB_DG_PAGOS', 'titulo': 'Pagos', 'labelSql': "CONCAT('#', id)", 'ro': ['creado_en', 'actualizado_en'],
        'cols': [
            FK('pedido_id', 'pedidos'), T('pasarela', 30), T('referencia_externa', 80, False),
            OP('estado', ['pendiente', 'aprobado', 'rechazado', 'reembolsado'], True, 'pendiente'), N('monto'),
            {**T('moneda', 3), 'def': 'COP'}, OP('metodo_tipo', ['tarjeta', 'pse', 'nequi'], True, 'tarjeta'),
            T('marca', 20, False), T('ultimos4', 4, False),
        ],
    },
}

_PUBLICOS = ('n', 't', 'req', 'max', 'op', 'ref', 'tipo', 'min', 'def')
_FALTA = object()


def columnas_ver(d):
    return ['id', *[c['n'] for c in d['cols'] if c['t'] != 'secreto'], *d.get('ro', [])]


def esquema_publico():
    return [{'clave': k, 'titulo': d['titulo'], 'ver': columnas_ver(d),
             'cols': [{x: c[x] for x in _PUBLICOS if x in c} for c in d['cols']]} for k, d in TABLAS.items()]


def _err(msg): return HttpError(400, msg)
def _vacio(v): return v is None or (isinstance(v, str) and v.strip() == '')


def _numero(raw):
    try:
        n = float(raw)
    except (TypeError, ValueError):
        return None
    return n if math.isfinite(n) else None


def convertir(c, raw):
    campo = c['n'].replace('_', ' ')
    t = c['t']
    if t == 'bool':
        if raw in (True, 1, '1', 'true'):
            return 1
        if raw in (False, 0, '0', 'false'):
            return 0
        raise _err(f'Valor no válido en {campo}.')
    if _vacio(raw):
        if c['req']:
            raise _err(f'El campo {campo} es obligatorio.')
        return None
    if t == 'texto':
        s = str(raw).strip()
        if len(s) > c['max']:
            raise _err(f"{campo}: máximo {c['max']} caracteres.")
        return s
    if t in ('entero', 'fk'):
        n = _numero(raw)
        if n is None or n != int(n):
            raise _err(f'{campo}: debe ser un número entero.')
        n = int(n)
        if (n < 1) if t == 'fk' else (n < c.get('min', 0)):
            raise _err(f'{campo}: valor fuera de rango.')
        if n > 2147483647:
            raise _err(f'{campo}: valor demasiado grande.')
        return n
    if t == 'decimal':
        n = _numero(raw)
        if n is None or n <= 0 or n >= 100:
            raise _err(f'{campo}: debe estar entre 0.01 y 99.99.')
        return math.floor(n * 100 + 0.5) / 100
    if t == 'enum':
        if raw not in c['op']:
            raise _err(f'{campo}: opción no válida.')
        return raw
    if t == 'hex':
        if not re.fullmatch(r'#[0-9a-fA-F]{6}', str(raw)):
            raise _err(f'{campo}: usa el formato #rrggbb.')
        return str(raw).lower()
    raise _err(f"Tipo de campo no soportado: {c['n']}.")


def construir_valores(d, body, modo, hash_fn):
    if not isinstance(body, dict):
        raise _err('Datos no válidos.')
    if d.get('validar'):
        d['validar'](body, modo)
    out = {}
    for c in d['cols']:
        raw = body.get(c['n'], _FALTA)
        campo = c['n'].replace('_', ' ')
        if c['t'] == 'secreto':
            s = '' if raw in (_FALTA, None) else str(raw)
            if not s:
                if modo == 'crear' and c['req']:
                    raise _err(f'El campo {campo} es obligatorio.')
                continue
            if len(s) < c['min'] or len(s) > 72:
                raise _err(f"{campo}: entre {c['min']} y 72 caracteres.")
            out[c['col']] = hash_fn(s)
            continue
        if raw is _FALTA:
            if modo == 'editar':
                continue
            if 'def' in c:
                out[c['n']] = c['def']
                continue
            raw = None
        out[c['n']] = convertir(c, raw)
    return out


def sql_insertar(d, valores):
    cols = list(valores)
    if not cols:
        raise _err('No hay datos para guardar.')
    return (f"INSERT INTO {d['tabla']} ({', '.join(f'`{c}`' for c in cols)}) VALUES ({', '.join('?' for _ in cols)})", list(valores.values()))


def sql_actualizar(d, valores, id):
    cols = list(valores)
    if not cols:
        raise _err('No hay cambios para guardar.')
    return (f"UPDATE {d['tabla']} SET {', '.join(f'`{c}` = ?' for c in cols)} WHERE id = ?", [*valores.values(), id])


def error_amigable(e):
    n = errno_de(e)
    if n == 1062:
        return {'status': 409, 'message': 'Ya existe un registro con ese valor único (correo, código, nombre, hex...).'}
    if n in (1451, 1217):
        return {'status': 409, 'message': 'No se puede eliminar: otros registros dependen de este (por ejemplo un pedido con pagos).'}
    if n in (1452, 1216):
        return {'status': 400, 'message': 'Uno de los registros relacionados (llave foránea) no existe.'}
    if n in (3819, 4025):
        return {'status': 400, 'message': 'Los datos no cumplen una regla de la tabla (por ejemplo: total = subtotal + envío, o el admin necesita código).'}
    if n in (1406, 1292, 1264, 1048):
        return {'status': 400, 'message': 'Hay un dato con formato, tamaño o valor no válido.'}
    return None


def filtros_auditoria(q=None):
    q = q or {}
    where, params = [], []

    def fecha(v, nombre):
        if _vacio(v):
            return None
        try:
            if not re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}', str(v)):
                raise ValueError
            datetime.strptime(str(v), '%Y-%m-%d')
        except ValueError:
            raise _err(f'Fecha "{nombre}" no válida (usa AAAA-MM-DD).')
        return str(v)

    desde, hasta = fecha(q.get('desde'), 'desde'), fecha(q.get('hasta'), 'hasta')
    if desde and hasta and desde > hasta:
        raise _err('La fecha "desde" no puede ser posterior a "hasta".')
    if desde:
        where.append('a.fecha >= ?'); params.append(desde)
    if hasta:
        where.append('a.fecha < DATE_ADD(?, INTERVAL 1 DAY)'); params.append(hasta)
    if not _vacio(q.get('tabla')):
        if not re.fullmatch(r'MB_DG_[A-Z_]{1,30}', str(q['tabla'])):
            raise _err('Tabla no válida.')
        where.append('a.tabla = ?'); params.append(str(q['tabla']))
    if not _vacio(q.get('operacion')):
        if q['operacion'] not in ('INSERT', 'UPDATE', 'DELETE'):
            raise _err('Operación no válida.')
        where.append('a.operacion = ?'); params.append(q['operacion'])
    return ('WHERE ' + ' AND '.join(where) if where else ''), params
