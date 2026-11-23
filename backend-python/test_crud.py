import json
import os
import pytest

os.environ.setdefault('JWT_SECRET', 'x' * 32)
from crud import TABLAS, columnas_ver, construir_valores, error_amigable, esquema_publico, filtros_auditoria, sql_actualizar, sql_insertar
from errores import HttpError

hash_ = lambda s: f'hash({s})'


def falla(fn, texto=None):
    with pytest.raises(HttpError) as e:
        fn()
    assert e.value.status == 400 and (not texto or texto in e.value.message)


def test_crear_auto_valido():
    v = construir_valores(TABLAS['autos'], {'marca': ' Vektra ', 'nombre': 'Nova', 'carroceria': 'gt', 'color_base': '#C81E3A'}, 'crear', hash_)
    assert v == {'marca': 'Vektra', 'nombre': 'Nova', 'carroceria': 'gt', 'color_base': '#c81e3a', 'activo': 1}


def test_validaciones_basicas():
    b = {'marca': 'a', 'nombre': 'x', 'carroceria': 'gt', 'color_base': '#000000'}
    falla(lambda: construir_valores(TABLAS['autos'], {**b, 'marca': ''}, 'crear', hash_), 'obligatorio')
    falla(lambda: construir_valores(TABLAS['autos'], {**b, 'carroceria': 'camion'}, 'crear', hash_), 'opción')
    falla(lambda: construir_valores(TABLAS['autos'], {**b, 'color_base': 'rojo'}, 'crear', hash_), '#rrggbb')
    falla(lambda: construir_valores(TABLAS['autos'], {**b, 'marca': 'a' * 61}, 'crear', hash_), 'máximo')


def test_enteros():
    b = {'nombre': 'R', 'estilo': 'five', 'acabado_base': '#c9ccd1'}
    for malo in ('12.5', -1, 'abc'):
        falla(lambda: construir_valores(TABLAS['rines'], {**b, 'precio': malo}, 'crear', hash_))
    assert construir_valores(TABLAS['rines'], {**b, 'precio': '1890000'}, 'crear', hash_)['precio'] == 1890000


def test_editar_parcial_y_nulos():
    assert construir_valores(TABLAS['rines'], {'precio': 2000000}, 'editar', hash_) == {'precio': 2000000}
    assert construir_valores(TABLAS['configuraciones'], {'auto_id': '', 'ancho_rin': ''}, 'editar', hash_) == {'auto_id': None, 'ancho_rin': None}


def test_usuarios_hash():
    v = construir_valores(TABLAS['usuarios'], {'email': 'a@b.co', 'rol': 'admin', 'password': 'secreta1', 'codigo_acceso': 'AR-1'}, 'crear', hash_)
    assert v['password_hash'] == 'hash(secreta1)' and v['codigo_acceso_hash'] == 'hash(AR-1)'
    assert 'password' not in v and 'codigo_acceso' not in v
    falla(lambda: construir_valores(TABLAS['usuarios'], {'email': 'a@b.co', 'rol': 'admin', 'password': 'secreta1'}, 'crear', hash_), 'código de acceso')
    falla(lambda: construir_valores(TABLAS['usuarios'], {'email': 'a@b.co', 'rol': 'cliente', 'password': '123'}, 'crear', hash_), 'entre 6')
    assert construir_valores(TABLAS['usuarios'], {'email': 'n@b.co', 'password': ''}, 'editar', hash_) == {'email': 'n@b.co'}


def test_medidas_factor():
    b = {'tipo': 'rin', 'etiqueta': '23"'}
    assert construir_valores(TABLAS['medidas'], {**b, 'factor': '1.456'}, 'crear', hash_)['factor'] == 1.46
    falla(lambda: construir_valores(TABLAS['medidas'], {**b, 'factor': 100}, 'crear', hash_))
    falla(lambda: construir_valores(TABLAS['medidas'], {**b, 'factor': 0}, 'crear', hash_))


def test_pedidos_defaults():
    v = construir_valores(TABLAS['pedidos'], {'codigo': 'AR-111111', 'usuario_id': 1, 'nombre_completo': 'N', 'direccion': 'D', 'ciudad': 'C',
                                              'departamento': 'D', 'telefono': '1', 'subtotal': 10, 'total': 25010}, 'crear', hash_)
    assert v['costo_envio'] == 25000 and v['estado'] == 'pendiente'


def test_sql_parametrizado():
    sql, params = sql_insertar(TABLAS['colores'], {'nombre': "x'); DROP TABLE y;--", 'hex': '#000000'})
    assert sql == 'INSERT INTO MB_DG_COLORES (`nombre`, `hex`) VALUES (?, ?)'
    assert params == ["x'); DROP TABLE y;--", '#000000']
    sql, params = sql_actualizar(TABLAS['colores'], {'nombre': 'n'}, 7)
    assert sql == 'UPDATE MB_DG_COLORES SET `nombre` = ? WHERE id = ?' and params == ['n', 7]
    falla(lambda: sql_actualizar(TABLAS['colores'], {}, 1))


def test_esquema_sin_secretos():
    assert columnas_ver(TABLAS['usuarios']) == ['id', 'email', 'rol', 'creado_en']
    j = json.dumps(esquema_publico())
    assert 'password_hash' not in j and 'MB_DG_' not in j


def test_fk_validas():
    for d in TABLAS.values():
        for c in d['cols']:
            if c['t'] == 'fk':
                assert c['ref'] in TABLAS


def test_errores_mysql():
    class E(Exception):
        def __init__(s, n): s.errno = n
    assert error_amigable(E(1062))['status'] == 409
    assert error_amigable(E(1451))['status'] == 409
    assert error_amigable(E(1452))['status'] == 400
    assert error_amigable(E(4025))['status'] == 400 and error_amigable(E(3819))['status'] == 400
    assert error_amigable(Exception('otro')) is None


def test_filtros_auditoria():
    assert filtros_auditoria({}) == ('', [])
    w, p = filtros_auditoria({'desde': '2026-11-01', 'hasta': '2026-11-19', 'tabla': 'MB_DG_PEDIDOS', 'operacion': 'UPDATE'})
    assert w == 'WHERE a.fecha >= ? AND a.fecha < DATE_ADD(?, INTERVAL 1 DAY) AND a.tabla = ? AND a.operacion = ?'
    assert p == ['2026-11-01', '2026-11-19', 'MB_DG_PEDIDOS', 'UPDATE']
    falla(lambda: filtros_auditoria({'desde': '2026-13-45'}), 'no válida')
    falla(lambda: filtros_auditoria({'desde': '1; DROP'}), 'no válida')
    falla(lambda: filtros_auditoria({'desde': '2026-11-20', 'hasta': '2026-11-01'}), 'posterior')
    falla(lambda: filtros_auditoria({'tabla': "x' OR 1=1"}), 'Tabla')
    falla(lambda: filtros_auditoria({'operacion': 'DROP'}), 'Operación')


def test_bcryptjs_interop():
    from auth import check_pw, hash_pw
    assert check_pw('secreta1', '$2a$10$aYFVyj5Z1CkscaE0KQf8fef5gvOzsNzzp8VHZEIsqVOw3En5QkfK2')
    assert not check_pw('otra', '$2a$10$aYFVyj5Z1CkscaE0KQf8fef5gvOzsNzzp8VHZEIsqVOw3En5QkfK2')
    h = hash_pw('clave123')
    assert len(h) == 60 and check_pw('clave123', h)


@pytest.fixture
def cliente():
    from app import app
    return app.test_client()


def token(rol):
    from auth import firmar
    return {'Authorization': 'Bearer ' + firmar({'id': 1, 'rol': rol}, 600)}


def test_http_sin_db(cliente):
    r = cliente.get('/api/nada')
    assert r.status_code == 404 and r.json == {'error': 'Ruta no encontrada.'}
    r = cliente.post('/api/auth/login', data='{mal', content_type='application/json')
    assert r.status_code == 400 and r.json['error'] == 'JSON no válido.'
    assert cliente.post('/api/pedidos', json={}).status_code == 401
    assert cliente.get('/api/admin/tablas').status_code == 401
    assert cliente.get('/api/admin/tablas', headers=token('cliente')).status_code == 403
    r = cliente.get('/api/admin/tablas', headers=token('admin'))
    assert r.status_code == 200 and {t['clave'] for t in r.json} == set(TABLAS)
    assert cliente.get('/api/admin/tablas/x', headers=token('admin')).json['error'] == 'Tabla no encontrada.'
    assert cliente.put('/api/admin/tablas/autos/abc', json={}, headers=token('admin')).json['error'] == 'Id no válido.'
    r = cliente.post('/api/pedidos', json={'envio': {}, 'items': [{}]}, headers=token('cliente'))
    assert r.status_code == 400 and r.json['error'] == 'Revisa el campo nombre.'
    r = cliente.post('/api/auth/register', json={'email': 'mal', 'password': '123456'})
    assert r.status_code == 400 and r.json['error'] == 'Correo no válido.'


def test_estadisticas_requiere_admin(cliente):
    assert cliente.get('/api/admin/estadisticas').status_code == 401
    assert cliente.get('/api/admin/estadisticas', headers=token('cliente')).status_code == 403
    assert cliente.get('/api/admin/estadisticas?anio=1', headers=token('admin')).json['error'] == 'Año no válido.'
