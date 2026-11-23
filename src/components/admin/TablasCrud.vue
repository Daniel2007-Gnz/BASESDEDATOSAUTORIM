<script setup>
import { ref, computed, onMounted } from 'vue'
import { api } from '../../api'
import { adminLogout } from '../../store'

const esquema = ref([])
const clave = ref('autos')
const filas = ref([])
const total = ref(0), pagina = ref(1), paginas = ref(1)
const q = ref('')
const error = ref(''), aviso = ref('')
const form = ref(null) // null = cerrado · { id: null | número, valores: {} }
const opciones = ref({}) // 'tabla|tipo' -> [{ id, label }]
const guardando = ref(false)

const tabla = computed(() => esquema.value.find(t => t.clave === clave.value))
const tipoDe = n => tabla.value.cols.find(c => c.n === n)?.t
const titulo = n => n.replace(/_/g, ' ')
const esFecha = n => n === 'creado_en' || n === 'actualizado_en'
const clavesOpc = c => `${c.ref}|${c.tipo ?? ''}`

function fallo(e) {
  if (e.status === 401 || e.status === 403) adminLogout()
  else error.value = e.message
}

async function cargar() {
  error.value = ''
  try {
    const d = await api(`/admin/tablas/${clave.value}?pagina=${pagina.value}&q=${encodeURIComponent(q.value)}`, { admin: true })
    filas.value = d.filas; total.value = d.total; paginas.value = d.paginas
    if (pagina.value > d.paginas) { pagina.value = d.paginas; await cargar() }
  } catch (e) { fallo(e) }
}

function elegir(c) { clave.value = c; pagina.value = 1; q.value = ''; form.value = null; aviso.value = ''; cargar() }
function ir(p) { pagina.value = Math.min(Math.max(1, p), paginas.value); cargar() }

async function cargarOpciones() {
  const pendientes = tabla.value.cols.filter(c => c.t === 'fk' && !opciones.value[clavesOpc(c)])
  await Promise.all(pendientes.map(async c => {
    const t = c.tipo ? `?tipo=${c.tipo}` : ''
    opciones.value[clavesOpc(c)] = await api(`/admin/tablas/${c.ref}/opciones${t}`, { admin: true })
  }))
}

async function abrir(fila) {
  error.value = ''; aviso.value = ''
  const valores = {}
  for (const c of tabla.value.cols) {
    if (c.t === 'secreto') valores[c.n] = ''
    else if (fila) valores[c.n] = c.t === 'bool' ? !!fila[c.n] : fila[c.n] ?? ''
    else if (c.t === 'bool') valores[c.n] = c.def === 1
    else valores[c.n] = c.def ?? (c.t === 'hex' ? '#000000' : '')
  }
  try { await cargarOpciones() } catch (e) { return fallo(e) }
  form.value = { id: fila?.id ?? null, valores }
}

async function guardar() {
  error.value = ''; guardando.value = true
  try {
    const f = form.value
    await api(f.id ? `/admin/tablas/${clave.value}/${f.id}` : `/admin/tablas/${clave.value}`, {
      method: f.id ? 'PUT' : 'POST', body: f.valores, admin: true,
    })
    aviso.value = f.id ? `Registro #${f.id} actualizado.` : 'Registro creado.'
    form.value = null
    await cargar()
  } catch (e) { fallo(e) } finally { guardando.value = false }
}

async function eliminar(fila) {
  if (!confirm(`¿Eliminar el registro #${fila.id} de "${tabla.value.titulo}"? Esta acción no se puede deshacer.`)) return
  error.value = ''; aviso.value = ''
  try {
    await api(`/admin/tablas/${clave.value}/${fila.id}`, { method: 'DELETE', admin: true })
    aviso.value = `Registro #${fila.id} eliminado.`
    await cargar()
  } catch (e) { fallo(e) }
}

const celda = (fila, n) => {
  const v = fila[n]
  if (v === null || v === undefined) return '—'
  if (esFecha(n)) return new Date(v).toLocaleString('es-CO')
  if (tipoDe(n) === 'bool') return v ? 'Sí' : 'No'
  return v
}

onMounted(async () => {
  try { esquema.value = await api('/admin/tablas', { admin: true }); await cargar() } catch (e) { fallo(e) }
})
</script>

<template>
  <div v-if="tabla">
    <div class="d-flex gap-2 flex-wrap mb-3">
      <button v-for="t in esquema" :key="t.clave" class="btn btn-sm" :class="t.clave === clave ? 'btn-red' : 'btn-outline-light'" @click="elegir(t.clave)">{{ t.titulo }}</button>
    </div>

    <div v-if="error" class="alert alert-danger py-2 small">{{ error }}</div>
    <div v-if="aviso" class="alert alert-success py-2 small">{{ aviso }}</div>

    <div class="d-flex gap-2 flex-wrap align-items-center mb-3">
      <h2 class="h5 mb-0 me-auto">{{ tabla.titulo }} <span class="text-secondary small">({{ total }})</span></h2>
      <form class="d-flex gap-2" @submit.prevent="pagina = 1; cargar()">
        <input v-model="q" class="form-control form-control-sm" placeholder="Buscar…" aria-label="Buscar" style="width:200px" />
        <button class="btn btn-sm btn-outline-light">Buscar</button>
      </form>
      <button class="btn btn-sm btn-red" @click="abrir(null)">+ Nuevo</button>
    </div>

    <form v-if="form" class="panel p-3 mb-3" @submit.prevent="guardar">
      <h3 class="h6 mb-3">{{ form.id ? `Editar registro #${form.id}` : 'Nuevo registro' }}</h3>
      <div class="row g-3">
        <div v-for="c in tabla.cols" :key="c.n" class="col-md-4">
          <label class="form-label small text-capitalize" :for="'f_' + c.n">{{ titulo(c.n) }}<span v-if="c.req && c.t !== 'bool' && !(c.t === 'secreto' && form.id)" class="text-red"> *</span></label>
          <div v-if="c.t === 'bool'" class="form-check form-switch"><input :id="'f_' + c.n" v-model="form.valores[c.n]" type="checkbox" class="form-check-input" role="switch" /></div>
          <select v-else-if="c.t === 'enum'" :id="'f_' + c.n" v-model="form.valores[c.n]" class="form-select" :required="c.req">
            <option v-if="!c.req" value="">— ninguno —</option>
            <option v-for="o in c.op" :key="o" :value="o">{{ o }}</option>
          </select>
          <select v-else-if="c.t === 'fk'" :id="'f_' + c.n" v-model="form.valores[c.n]" class="form-select" :required="c.req">
            <option v-if="!c.req" value="">— ninguno —</option>
            <option v-for="o in opciones[c.ref + '|' + (c.tipo ?? '')]" :key="o.id" :value="o.id">{{ o.label }} (id {{ o.id }})</option>
          </select>
          <input v-else-if="c.t === 'hex'" :id="'f_' + c.n" v-model="form.valores[c.n]" type="color" class="form-control form-control-color" />
          <input v-else-if="c.t === 'secreto'" :id="'f_' + c.n" v-model="form.valores[c.n]" type="password" class="form-control" autocomplete="new-password"
            :placeholder="form.id ? 'Vacío = no cambiar' : ''" :required="c.req && !form.id" />
          <input v-else :id="'f_' + c.n" v-model="form.valores[c.n]" class="form-control"
            :type="c.t === 'entero' ? 'number' : c.t === 'decimal' ? 'number' : 'text'" :step="c.t === 'decimal' ? '0.01' : undefined"
            :min="c.t === 'entero' ? c.min : undefined" :maxlength="c.max" :required="c.req" />
        </div>
      </div>
      <div class="d-flex gap-2 mt-3">
        <button class="btn btn-red btn-sm" :disabled="guardando">{{ guardando ? 'Guardando…' : 'Guardar' }}</button>
        <button type="button" class="btn btn-outline-light btn-sm" @click="form = null">Cancelar</button>
      </div>
    </form>

    <div class="panel p-3 table-responsive">
      <table class="table align-middle mb-0 small">
        <thead><tr><th v-for="n in tabla.ver" :key="n" class="text-capitalize">{{ titulo(n) }}</th><th class="text-end">Acciones</th></tr></thead>
        <tbody>
          <tr v-for="f in filas" :key="f.id">
            <td v-for="n in tabla.ver" :key="n">
              <span v-if="tipoDe(n) === 'hex'" class="d-inline-block rounded-circle me-1 align-middle border" :style="{ background: f[n], width: '14px', height: '14px' }"></span>{{ celda(f, n) }}
            </td>
            <td class="text-end text-nowrap">
              <button class="btn btn-sm btn-outline-light me-1" @click="abrir(f)">Editar</button>
              <button class="btn btn-sm btn-outline-danger" @click="eliminar(f)">Eliminar</button>
            </td>
          </tr>
          <tr v-if="!filas.length"><td :colspan="tabla.ver.length + 1" class="text-center text-secondary py-4">No hay registros.</td></tr>
        </tbody>
      </table>
    </div>

    <div v-if="paginas > 1" class="d-flex justify-content-center align-items-center gap-3 mt-3">
      <button class="btn btn-sm btn-outline-light" :disabled="pagina <= 1" @click="ir(pagina - 1)">← Anterior</button>
      <span class="small text-secondary">Página {{ pagina }} de {{ paginas }}</span>
      <button class="btn btn-sm btn-outline-light" :disabled="pagina >= paginas" @click="ir(pagina + 1)">Siguiente →</button>
    </div>
  </div>
  <div v-else-if="error" class="alert alert-danger">{{ error }}</div>
</template>
