import math
import os
import random
import re
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from flask import Blueprint, Flask, g, jsonify, send_from_directory
from flask.json.provider import DefaultJSONProvider
from flask_cors import CORS
from sqlalchemy.exc import IntegrityError
from werkzeug.middleware.proxy_fix import ProxyFix
from db import consultar, engine, run, transaccion
from auth import DUMMY_HASH, check_config, check_pw, firmar, hash_pw, limitar_login, requiere
from errores import HttpError, cuerpo, errno_de, registrar
from admin import bp as admin_bp

DIST = Path(__file__).resolve().parent.parent / 'dist'
EMAIL_RE = re.compile(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
ANCHOS = ['7.5J', '8.5J', '9.5J']
COSTO_ENVIO = 25000
COLS = ['tipo', 'nombre', 'detalle', 'precio_unitario', 'auto_id', 'color_id', 'rin_id', 'acabado_id',
        'medida_rin_id', 'ancho_rin', 'llanta_id', 'medida_llanta_id']

pub = Blueprint('pub', __name__, url_prefix='/api')


class Json(DefaultJSONProvider):
    ensure_ascii = False
    sort_keys = False

    @staticmethod
    def default(o):
        if isinstance(o, Decimal):
            return str(o)
        if isinstance(o, datetime):
            return o.isoformat(timespec='milliseconds') + 'Z'
        if isinstance(o, date):
            return o.isoformat()
        return DefaultJSONProvider.default(o)


def s(v):
    return '' if v is None else str(v)


def entero(v):
    return isinstance(v, int) and not isinstance(v, bool) or isinstance(v, float) and v.is_integer()


def pid(v):
    return int(v) if entero(v) else None


def redondear(n):
    return math.floor(n / 1000 + 0.5) * 1000


def texto(v, mx, campo):
    t = s(v).strip()
    if not t or len(t) > mx:
        raise HttpError(400, f'Revisa el campo {campo}.')
    return t


def uno(conn, sql, params, msg):
    row = run(conn, sql, params).mappings().first()
    if not row:
        raise HttpError(400, msg)
    return dict(row)


def construir_configuracion(conn, cfg):
    if not isinstance(cfg, dict):
        raise HttpError(400, 'Producto no válido.')
    tipo = cfg.get('tipo')
    if tipo == 'kit':
        auto = uno(conn, 'SELECT id, nombre FROM MB_DG_AUTOS WHERE id = ? AND activo', [pid(cfg.get('autoId'))], 'Auto no disponible.')
        rin = uno(conn, 'SELECT id, nombre, precio FROM MB_DG_RINES WHERE id = ? AND activo', [pid(cfg.get('rinId'))], 'Rin no disponible.')
        llanta = uno(conn, 'SELECT id, nombre, precio FROM MB_DG_LLANTAS WHERE id = ? AND activo', [pid(cfg.get('llantaId'))], 'Llanta no disponible.')
        color = None if cfg.get('colorId') is None else uno(conn, 'SELECT id, nombre FROM MB_DG_COLORES WHERE id = ?', [pid(cfg['colorId'])], 'Color no disponible.')
        return {
            'tipo': 'kit', 'nombre': auto['nombre'],
            'detalle': f"{color['nombre'] if color else 'Color base'} · {rin['nombre']} · {llanta['nombre']}",
            'precio_unitario': rin['precio'] + llanta['precio'],
            'auto_id': auto['id'], 'color_id': color['id'] if color else None, 'rin_id': rin['id'], 'llanta_id': llanta['id'],
        }
    if tipo == 'rines':
        rin = uno(conn, 'SELECT id, nombre, precio FROM MB_DG_RINES WHERE id = ? AND activo', [pid(cfg.get('rinId'))], 'Rin no disponible.')
        medida = uno(conn, "SELECT id, etiqueta, factor FROM MB_DG_MEDIDAS WHERE id = ? AND tipo = 'rin'", [pid(cfg.get('medidaRinId'))], 'Medida de rin no válida.')
        if cfg.get('ancho') not in ANCHOS:
            raise HttpError(400, 'Ancho de rin no válido.')
        acabado = None if cfg.get('acabadoId') is None else uno(conn, 'SELECT id, nombre FROM MB_DG_ACABADOS WHERE id = ?', [pid(cfg['acabadoId'])], 'Acabado no disponible.')
        return {
            'tipo': 'rines', 'nombre': rin['nombre'],
            'detalle': f"Set de 4 · {acabado['nombre'] if acabado else 'Original'} · {medida['etiqueta']} · {cfg['ancho']}",
            'precio_unitario': redondear(rin['precio'] * float(medida['factor'])),
            'rin_id': rin['id'], 'acabado_id': acabado['id'] if acabado else None, 'medida_rin_id': medida['id'], 'ancho_rin': cfg['ancho'],
        }
    if tipo == 'llantas':
        llanta = uno(conn, 'SELECT id, nombre, precio FROM MB_DG_LLANTAS WHERE id = ? AND activo', [pid(cfg.get('llantaId'))], 'Llanta no disponible.')
        medida = uno(conn, "SELECT id, etiqueta, factor FROM MB_DG_MEDIDAS WHERE id = ? AND tipo = 'llanta'", [pid(cfg.get('medidaLlantaId'))], 'Medida de llanta no válida.')
        return {
            'tipo': 'llantas', 'nombre': llanta['nombre'], 'detalle': f"Set de 4 · {medida['etiqueta']}",
            'precio_unitario': redondear(llanta['precio'] * float(medida['factor'])),
            'llanta_id': llanta['id'], 'medida_llanta_id': medida['id'],
        }
    raise HttpError(400, 'Tipo de producto no válido.')


@pub.get('/catalogo')
def catalogo():
    return jsonify(
        autos=consultar('SELECT id, marca, nombre, carroceria, color_base FROM MB_DG_AUTOS WHERE activo ORDER BY id'),
        colores=consultar('SELECT id, nombre, hex FROM MB_DG_COLORES ORDER BY id'),
        acabados=consultar('SELECT id, nombre, hex FROM MB_DG_ACABADOS ORDER BY id'),
        rines=consultar('SELECT id, nombre, estilo, acabado_base, precio FROM MB_DG_RINES WHERE activo ORDER BY id'),
        llantas=consultar('SELECT id, codigo, nombre, svg_radio, svg_radio_rin, precio FROM MB_DG_LLANTAS WHERE activo ORDER BY id'),
        medidas=consultar('SELECT id, tipo, etiqueta, factor FROM MB_DG_MEDIDAS ORDER BY tipo, factor'))


@pub.post('/auth/register')
def register():
    limitar_login()
    b = cuerpo()
    email, password = s(b.get('email')).strip().lower(), s(b.get('password'))
    if not EMAIL_RE.match(email) or len(email) > 190:
        raise HttpError(400, 'Correo no válido.')
    if not 6 <= len(password) <= 72:
        raise HttpError(400, 'La contraseña debe tener entre 6 y 72 caracteres.')
    try:
        with engine.begin() as c:
            uid = run(c, 'INSERT INTO MB_DG_USUARIOS (email, password_hash) VALUES (?, ?)', (email, hash_pw(password))).lastrowid
    except IntegrityError as e:
        if errno_de(e) == 1062:
            raise HttpError(409, 'Ese correo ya tiene una cuenta.')
        raise
    return jsonify(token=firmar({'id': uid, 'rol': 'cliente'}, 7 * 86400), user={'email': email, 'rol': 'cliente'}), 201


@pub.post('/auth/login')
def login():
    fallo, exito = limitar_login()
    b = cuerpo()
    email, password = s(b.get('email')).strip().lower(), s(b.get('password'))
    u = (consultar('SELECT id, email, password_hash, rol FROM MB_DG_USUARIOS WHERE email = ?', [email]) or [None])[0]
    if not u:
        fallo()
        raise HttpError(404, 'Cuenta no encontrada.', code='no_account')
    if not check_pw(password, u['password_hash']):
        fallo()
        raise HttpError(401, 'La contraseña no es correcta.')
    exito()
    return jsonify(token=firmar(u, 7 * 86400), user={'email': u['email'], 'rol': u['rol']})


@pub.post('/auth/admin-login')
def admin_login():
    fallo, exito = limitar_login()
    b = cuerpo()
    email, password, code = s(b.get('email')).strip().lower(), s(b.get('password')), s(b.get('code'))
    u = (consultar("SELECT id, email, password_hash, codigo_acceso_hash, rol FROM MB_DG_USUARIOS WHERE email = ? AND rol = 'admin'", [email]) or [None])[0]
    ok_pass = check_pw(password, u['password_hash'] if u else DUMMY_HASH)
    ok_code = check_pw(code, (u or {}).get('codigo_acceso_hash') or DUMMY_HASH)
    if not u or not ok_pass or not ok_code:
        fallo()
        raise HttpError(401, 'Correo, contraseña o código incorrectos.')
    exito()
    return jsonify(token=firmar(u, 8 * 3600), user={'email': u['email'], 'rol': u['rol']})


@pub.post('/pedidos')
@requiere()
def crear_pedido():
    b = cuerpo()
    envio, items = b.get('envio'), b.get('items')
    if not isinstance(envio, dict) or not isinstance(items, list) or not 1 <= len(items) <= 50:
        raise HttpError(400, 'Pedido no válido.')
    dir_ = {
        'nombre': texto(envio.get('name'), 120, 'nombre'), 'direccion': texto(envio.get('address'), 200, 'dirección'),
        'ciudad': texto(envio.get('city'), 80, 'ciudad'), 'departamento': texto(envio.get('state'), 80, 'departamento'),
        'telefono': texto(envio.get('phone'), 30, 'teléfono'),
    }
    pago = b.get('pago') if isinstance(b.get('pago'), dict) else {}
    ultimos4, marca = s(pago.get('ultimos4')), s(pago.get('marca'))
    if not re.fullmatch(r'[0-9]{4}', ultimos4) or not re.fullmatch(r'[a-z]{1,20}', marca):
        raise HttpError(400, 'Datos de pago no válidos.')
    uid = g.user['id']

    def tx(conn):
        lineas = []
        for it in items:
            qty = it.get('qty') if isinstance(it, dict) else None
            if not entero(qty) or not 1 <= qty <= 99:
                raise HttpError(400, 'Cantidad no válida.')
            lineas.append((construir_configuracion(conn, it.get('pedido')), int(qty)))
        subtotal = sum(c['precio_unitario'] * q for c, q in lineas)
        total = subtotal + COSTO_ENVIO
        pedido_id = codigo = None
        for _ in range(5):
            codigo = f'AR-{random.randrange(10**6):06d}'
            try:
                pedido_id = run(conn, """INSERT INTO MB_DG_PEDIDOS (codigo, usuario_id, nombre_completo, direccion, ciudad, departamento, telefono, subtotal, costo_envio, total, estado)
                    VALUES (?,?,?,?,?,?,?,?,?,?, 'pagado')""",
                    (codigo, uid, dir_['nombre'], dir_['direccion'], dir_['ciudad'], dir_['departamento'], dir_['telefono'], subtotal, COSTO_ENVIO, total)).lastrowid
                break
            except IntegrityError as e:
                if errno_de(e) != 1062:
                    raise
        if not pedido_id:
            raise HttpError(500, 'No se pudo generar el código del pedido. Intenta de nuevo.')
        run(conn, """INSERT INTO MB_DG_PAGOS (pedido_id, pasarela, referencia_externa, estado, monto, metodo_tipo, marca, ultimos4)
            VALUES (?, 'simulada', ?, 'aprobado', ?, 'tarjeta', ?, ?)""", (pedido_id, f'SIM-{codigo}', total, marca, ultimos4))
        for cfg, qty in lineas:
            cid = run(conn, f"INSERT INTO MB_DG_CONFIGURACIONES ({','.join(COLS)}) VALUES ({','.join('?' for _ in COLS)})", [cfg.get(k) for k in COLS]).lastrowid
            run(conn, 'INSERT INTO MB_DG_PEDIDO_ITEMS (pedido_id, configuracion_id, cantidad) VALUES (?,?,?)', (pedido_id, cid, qty))
        return {'codigo': codigo, 'total': total}

    return jsonify(transaccion(uid, tx)), 201


def create_app():
    check_config()
    app = Flask(__name__, static_folder=None)
    app.json = Json(app)
    app.config['MAX_CONTENT_LENGTH'] = 50 * 1024
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1)
    CORS(app, resources={r'/api/*': {'origins': [o.strip() for o in (os.getenv('CORS_ORIGIN') or '*').split(',')]}})
    registrar(app)
    app.register_blueprint(pub)
    app.register_blueprint(admin_bp)
    if DIST.is_dir():
        @app.get('/', defaults={'ruta': ''})
        @app.get('/<path:ruta>')
        def spa(ruta):
            if ruta == 'api' or ruta.startswith('api/'):
                raise HttpError(404, 'Ruta no encontrada.')
            return send_from_directory(DIST, ruta if ruta and (DIST / ruta).is_file() else 'index.html')
    return app


app = create_app()

if __name__ == '__main__':
    app.run(host=os.getenv('HOST') or '127.0.0.1', port=int(os.getenv('PORT') or 3001), debug=False)
