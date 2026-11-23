import os
import re
from pathlib import Path
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

_raiz = Path(__file__).resolve().parent
load_dotenv(_raiz.parent / '.env')
load_dotenv(_raiz / '.env')


def _url():
    u = os.getenv('DATABASE_URL')
    if u:
        return re.sub(r'^mysql(\+\w+)?://', 'mysql+pymysql://', u)
    return URL.create(
        'mysql+pymysql', username=os.getenv('DB_USER') or 'root', password=os.getenv('DB_PASSWORD') or '',
        host=os.getenv('DB_HOST') or '127.0.0.1', port=int(os.getenv('DB_PORT') or 3306), database=os.getenv('DB_NAME') or 'autorim')


engine = create_engine(_url(), connect_args={'charset': 'utf8mb4'}, pool_size=10, pool_pre_ping=True, pool_recycle=1800)


def run(conn, sql, params=()):
    it = iter(range(len(params)))
    return conn.execute(text(re.sub(r'\?', lambda _: f':p{next(it)}', sql)), {f'p{i}': v for i, v in enumerate(params)})


def consultar(sql, params=()):
    with engine.connect() as c:
        return [dict(r) for r in run(c, sql, params).mappings()]


def transaccion(usuario_id, fn):
    conn = engine.connect()
    try:
        with conn.begin():
            run(conn, 'SET @app_usuario_id = ?', (usuario_id,))
            return fn(conn)
    finally:
        try:
            run(conn, 'SET @app_usuario_id = NULL')
            conn.commit()
        except Exception:
            pass
        conn.close()
