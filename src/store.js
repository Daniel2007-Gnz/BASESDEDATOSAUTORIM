import { reactive, computed, watch } from 'vue'
import { api, setToken } from './api'

export const fmt = n => new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 }).format(n)

// Catálogo: ya no está escrito aquí, se carga desde MySQL (loadCatalog) antes de montar la app.
// Se mantienen las mismas formas que usaban las vistas (brand, name, body, finish, R, rimR...).
export const cars = reactive([])
export const colors = reactive([])
export const rims = reactive([])
export const tires = reactive([])
export const finishes = reactive([])
export const sizes = reactive([])
export const tireSizes = reactive([])

const fill = (arr, items) => arr.splice(0, arr.length, ...items)
const medidas = (lista, tipo) =>
  lista.filter(m => m.tipo === tipo).map(m => ({ id: m.id, l: m.etiqueta, f: Number(m.factor) }))

export async function loadCatalog() {
  const c = await api('/catalogo')
  fill(cars, c.autos.map(a => ({ id: a.id, brand: a.marca, name: a.nombre, body: a.carroceria, color: a.color_base })))
  fill(colors, c.colores.map(x => ({ id: x.id, name: x.nombre, hex: x.hex })))
  fill(finishes, c.acabados.map(x => ({ id: x.id, name: x.nombre, hex: x.hex })))
  fill(rims, c.rines.map(r => ({ id: r.id, name: r.nombre, style: r.estilo, finish: r.acabado_base, price: r.precio })))
  // id = código de la URL (/llanta/sport); dbId = id real en MB_DG_LLANTAS
  fill(tires, c.llantas.map(t => ({ id: t.codigo, dbId: t.id, name: t.nombre, R: t.svg_radio, rimR: t.svg_radio_rin, price: t.precio })))
  fill(sizes, medidas(c.medidas, 'rin'))
  fill(tireSizes, medidas(c.medidas, 'llanta'))
}

const load = (k, d) => { try { return JSON.parse(localStorage.getItem(k)) ?? d } catch { return d } }
export const store = reactive({
  // El carrito sigue en el navegador; solo se guarda en MySQL al pagar. Se descartan
  // ítems de versiones anteriores que no traen los ids que necesita el servidor.
  cart: load('ar_cart', []).filter(i => i.pedido),
  user: load('ar_user', null), admin: load('ar_admin', false),
})
watch(() => store.cart, v => localStorage.setItem('ar_cart', JSON.stringify(v)), { deep: true })
watch(() => store.user, v => localStorage.setItem('ar_user', JSON.stringify(v)))
watch(() => store.admin, v => localStorage.setItem('ar_admin', JSON.stringify(v)))

export function login({ token, user }) { setToken('user', token); store.user = { email: user.email } }
export function logout() { setToken('user', null); store.user = null }
export function adminLogin(token) { setToken('admin', token); store.admin = true }
export function adminLogout() { setToken('admin', null); store.admin = false }

export const cartCount = computed(() => store.cart.reduce((s, i) => s + i.qty, 0))
export const cartTotal = computed(() => store.cart.reduce((s, i) => s + i.price * i.qty, 0))
export const addToCart = item => store.cart.push({ ...item, uid: Date.now() + Math.random(), qty: 1 })
