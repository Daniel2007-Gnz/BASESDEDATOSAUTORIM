import json
from flask import jsonify, request
from werkzeug.exceptions import HTTPException


class HttpError(Exception):
    def __init__(self, status, message, **extra):
        super().__init__(message)
        self.status, self.message, self.extra = status, message, extra


def errno_de(e):
    n = getattr(e, 'errno', None)
    if n is None:
        a = getattr(getattr(e, 'orig', None) or e, 'args', ())
        n = a[0] if a and isinstance(a[0], int) else None
    return n


def cuerpo():
    raw = request.get_data()
    if not raw.strip() or request.mimetype != 'application/json':
        return {}
    try:
        d = json.loads(raw)
    except ValueError:
        raise HttpError(400, 'JSON no válido.')
    if not isinstance(d, (dict, list)):
        raise HttpError(400, 'JSON no válido.')
    return d if isinstance(d, dict) else {}


def registrar(app):
    @app.errorhandler(HttpError)
    def _http(e):
        return jsonify(error=e.message, **e.extra), e.status

    @app.errorhandler(HTTPException)
    def _werk(e):
        if e.code in (404, 405):
            return jsonify(error='Ruta no encontrada.'), 404
        if e.code == 413:
            return jsonify(error='Solicitud demasiado grande.'), 413
        return jsonify(error=e.description), e.code

    @app.errorhandler(Exception)
    def _gen(e):
        app.logger.exception(e)
        return jsonify(error='Error del servidor.'), 500
