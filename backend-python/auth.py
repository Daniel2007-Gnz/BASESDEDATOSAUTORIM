import os
import re
import time
from functools import wraps
import bcrypt
import jwt
from flask import g, request
from werkzeug.security import check_password_hash
from errores import HttpError


def secret():
    s = os.getenv('JWT_SECRET') or ''
    if len(s) < 16:
        raise RuntimeError('Falta JWT_SECRET (mínimo 16 caracteres) en el archivo .env')
    return s


check_config = secret


def firmar(usuario, segundos):
    ahora = int(time.time())
    return jwt.encode({'id': usuario['id'], 'rol': usuario['rol'], 'iat': ahora, 'exp': ahora + segundos}, secret(), algorithm='HS256')


def hash_pw(s):
    return bcrypt.hashpw(s.encode()[:72], bcrypt.gensalt(10)).decode()


def check_pw(s, h):
    if not h:
        return False
    if h.startswith('$2'):
        try:
            return bcrypt.checkpw(s.encode()[:72], h.encode())
        except ValueError:
            return False
    return check_password_hash(h, s)


DUMMY_HASH = hash_pw('relleno-para-igualar-tiempos')


def autenticar(rol=None):
    m = re.fullmatch(r'Bearer (.+)', request.headers.get('Authorization', ''))
    if not m:
        raise HttpError(401, 'Inicia sesión para continuar.')
    try:
        g.user = jwt.decode(m[1], secret(), algorithms=['HS256'])
    except jwt.PyJWTError:
        raise HttpError(401, 'Tu sesión expiró. Vuelve a ingresar.')
    if rol and g.user.get('rol') != rol:
        raise HttpError(403, 'No tienes permiso para esto.')
    return g.user


def requiere(rol=None):
    def deco(f):
        @wraps(f)
        def w(*a, **k):
            autenticar(rol)
            return f(*a, **k)
        return w
    return deco


_intentos = {}
VENTANA, MAX = 15 * 60, 8


def limitar_login():
    ip = request.remote_addr
    r = _intentos.get(ip)
    if r and time.time() - r['desde'] < VENTANA and r['n'] >= MAX:
        raise HttpError(429, 'Demasiados intentos. Espera unos minutos.')

    def fallo():
        t, r = time.time(), _intentos.get(ip)
        if not r or t - r['desde'] >= VENTANA:
            _intentos[ip] = {'n': 1, 'desde': t}
        else:
            r['n'] += 1

    return fallo, lambda: _intentos.pop(ip, None)
