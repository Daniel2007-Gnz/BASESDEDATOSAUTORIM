import jwt from 'jsonwebtoken'
import { HttpError } from './errores.js'

export { HttpError }

const secret = () => {
  if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 16) {
    throw new Error('Falta JWT_SECRET (mínimo 16 caracteres) en el archivo .env')
  }
  return process.env.JWT_SECRET
}

export const checkConfig = () => secret()

export const firmar = (usuario, expiresIn) =>
  jwt.sign({ id: usuario.id, rol: usuario.rol }, secret(), { expiresIn })

// Middleware: exige un token válido y, opcionalmente, un rol concreto.
export const requiere = rol => (req, _res, next) => {
  const m = /^Bearer (.+)$/.exec(req.headers.authorization || '')
  if (!m) return next(new HttpError(401, 'Inicia sesión para continuar.'))
  try {
    req.user = jwt.verify(m[1], secret())
  } catch {
    return next(new HttpError(401, 'Tu sesión expiró. Vuelve a ingresar.'))
  }
  if (rol && req.user.rol !== rol) return next(new HttpError(403, 'No tienes permiso para esto.'))
  next()
}

// Limitador simple en memoria para frenar fuerza bruta en login (por IP).
const intentos = new Map()
const VENTANA = 15 * 60 * 1000, MAX = 8
export const limitarLogin = (req, _res, next) => {
  const ahora = Date.now()
  const reg = intentos.get(req.ip)
  if (reg && ahora - reg.desde < VENTANA && reg.n >= MAX) {
    return next(new HttpError(429, 'Demasiados intentos. Espera unos minutos.'))
  }
  req.fallo = () => {
    const r = intentos.get(req.ip)
    if (!r || ahora - r.desde >= VENTANA) intentos.set(req.ip, { n: 1, desde: ahora })
    else r.n++
  }
  req.exito = () => intentos.delete(req.ip)
  next()
}
