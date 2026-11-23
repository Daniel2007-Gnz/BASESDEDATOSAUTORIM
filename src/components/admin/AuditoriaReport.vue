<script setup>
import { ref, reactive, nextTick, onMounted } from 'vue'
import { api } from '../../api'
import { adminLogout } from '../../store'

const filtros = reactive({ desde: '', hasta: '', tabla: '', operacion: '' })
const datos = ref({ total: 0, pagina: 1, paginas: 1, tablas: [], resumen: [], filas: [] })
const error = ref('')
const cargando = ref(false)

const consulta = (extra = {}) => {
  const p = new URLSearchParams()
  for (const [k, v] of Object.entries({ ...filtros, ...extra })) if (v !== '' && v != null) p.set(k, v)
  return p.toString()
}

async function cargar(pagina = 1, todo = false) {
  error.value = ''; cargando.value = true
  try { datos.value = await api(`/admin/auditoria?${consulta(todo ? { todo: 1 } : { pagina })}`, { admin: true }) }
  catch (e) { if (e.status === 401 || e.status === 403) adminLogout(); else error.value = e.message }
  finally { cargando.value = false }
}
function limpiar() { Object.assign(filtros, { desde: '', hasta: '', tabla: '', operacion: '' }); cargar() }

const nombreTabla = t => t.replace('MB_DG_', '').toLowerCase()
const json = v => { if (v == null) return null; if (typeof v !== 'string') return v; try { return JSON.parse(v) } catch { return null } }

// Lista legible de lo que cambió: en UPDATE solo los campos distintos.
function cambios(f) {
  const antes = json(f.datos_anteriores), despues = json(f.datos_nuevos)
  if (f.operacion === 'INSERT') return Object.entries(despues ?? {}).map(([k, v]) => ({ k, despues: v }))
  if (f.operacion === 'DELETE') return Object.entries(antes ?? {}).map(([k, v]) => ({ k, antes: v }))
  return Object.keys(despues ?? {}).filter(k => JSON.stringify(antes?.[k]) !== JSON.stringify(despues[k]))
    .map(k => ({ k, antes: antes?.[k], despues: despues[k] }))
}
const fmtVal = v => (v === null || v === undefined ? 'NULL' : typeof v === 'object' ? JSON.stringify(v) : String(v))
const usuario = f => f.usuario_email || (f.usuario_app ? `usuario #${f.usuario_app}` : 'sin usuario de la app')
const resumenCambios = f => cambios(f).map(c =>
  f.operacion === 'UPDATE' ? `${c.k}: ${fmtVal(c.antes)} -> ${fmtVal(c.despues)}` : `${c.k}: ${fmtVal(f.operacion === 'INSERT' ? c.despues : c.antes)}`).join(' | ')

// CSV completo con los filtros actuales (hasta 5000 filas). Se neutralizan celdas que Excel leería como fórmula.
async function exportarCsv() {
  error.value = ''
  try {
    const d = await api(`/admin/auditoria?${consulta({ todo: 1 })}`, { admin: true })
    const cel = v => {
      let s = String(v ?? '')
      if (/^[=+\-@\t\r]/.test(s)) s = "'" + s
      return `"${s.replace(/"/g, '""')}"`
    }
    const cab = ['id', 'fecha', 'tabla', 'operacion', 'registro_id', 'usuario_app', 'usuario_bd', 'cambios']
    const lineas = d.filas.map(f => [f.id, f.fecha, f.tabla, f.operacion, f.registro_id, usuario(f), f.usuario_bd, resumenCambios(f)].map(cel).join(','))
    const blob = new Blob(['﻿' + [cab.join(','), ...lineas].join('\r\n')], { type: 'text/csv;charset=utf-8' })
    const a = Object.assign(document.createElement('a'), { href: URL.createObjectURL(blob), download: `auditoria_${filtros.desde || 'inicio'}_${filtros.hasta || 'hoy'}.csv` })
    a.click(); URL.revokeObjectURL(a.href)
  } catch (e) { error.value = e.message }
}
// Para imprimir se cargan todas las filas del filtro, no solo la página visible.
async function imprimir() { await cargar(1, true); await nextTick(); window.print() }

onMounted(() => cargar())
</script>

<template>
  <div>
    <h2 class="h5 mb-3">Reporte de auditoría por fecha</h2>
    <form class="panel p-3 mb-3 no-print row g-3 align-items-end" @submit.prevent="cargar()">
      <div class="col-6 col-md-2"><label class="form-label small" for="a_d">Desde</label><input id="a_d" v-model="filtros.desde" type="date" class="form-control form-control-sm" /></div>
      <div class="col-6 col-md-2"><label class="form-label small" for="a_h">Hasta</label><input id="a_h" v-model="filtros.hasta" type="date" class="form-control form-control-sm" /></div>
      <div class="col-6 col-md-3">
        <label class="form-label small" for="a_t">Tabla</label>
        <select id="a_t" v-model="filtros.tabla" class="form-select form-select-sm">
          <option value="">Todas</option><option v-for="t in datos.tablas" :key="t" :value="t">{{ nombreTabla(t) }}</option>
        </select>
      </div>
      <div class="col-6 col-md-2">
        <label class="form-label small" for="a_o">Operación</label>
        <select id="a_o" v-model="filtros.operacion" class="form-select form-select-sm">
          <option value="">Todas</option><option>INSERT</option><option>UPDATE</option><option>DELETE</option>
        </select>
      </div>
      <div class="col-12 col-md-3 d-flex gap-2 flex-wrap">
        <button class="btn btn-red btn-sm" :disabled="cargando">Consultar</button>
        <button type="button" class="btn btn-outline-light btn-sm" @click="limpiar">Limpiar</button>
        <button type="button" class="btn btn-outline-light btn-sm" @click="exportarCsv">CSV</button>
        <button type="button" class="btn btn-outline-light btn-sm" @click="imprimir">Imprimir</button>
      </div>
    </form>

    <div v-if="error" class="alert alert-danger py-2 small">{{ error }}</div>

    <p class="small text-secondary">
      {{ datos.total }} cambio(s)<span v-if="filtros.desde || filtros.hasta"> · del {{ filtros.desde || 'inicio' }} al {{ filtros.hasta || 'hoy' }}</span><span v-if="filtros.tabla"> · tabla {{ nombreTabla(filtros.tabla) }}</span><span v-if="filtros.operacion"> · {{ filtros.operacion }}</span>
    </p>

    <div class="panel p-3 table-responsive mb-4">
      <h3 class="h6">Resumen por día</h3>
      <table class="table table-sm align-middle mb-0 small">
        <thead><tr><th>Día</th><th class="text-end">Total</th><th class="text-end">Inserciones</th><th class="text-end">Actualizaciones</th><th class="text-end">Eliminaciones</th></tr></thead>
        <tbody>
          <tr v-for="d in datos.resumen" :key="d.dia"><td>{{ d.dia }}</td><td class="text-end">{{ d.total }}</td><td class="text-end">{{ d.inserts }}</td><td class="text-end">{{ d.updates }}</td><td class="text-end">{{ d.deletes }}</td></tr>
          <tr v-if="!datos.resumen.length"><td colspan="5" class="text-center text-secondary py-3">Sin cambios en este rango.</td></tr>
        </tbody>
      </table>
    </div>

    <div class="panel p-3 table-responsive">
      <h3 class="h6">Detalle de cambios</h3>
      <table class="table table-sm align-middle mb-0 small">
        <thead><tr><th>Fecha</th><th>Tabla</th><th>Operación</th><th>Registro</th><th>Usuario</th><th>Cambios</th></tr></thead>
        <tbody>
          <tr v-for="f in datos.filas" :key="f.id">
            <td class="text-nowrap">{{ f.fecha }}</td>
            <td>{{ nombreTabla(f.tabla) }}</td>
            <td><span class="badge" :class="{ 'text-bg-success': f.operacion === 'INSERT', 'text-bg-warning': f.operacion === 'UPDATE', 'text-bg-danger': f.operacion === 'DELETE' }">{{ f.operacion }}</span></td>
            <td>#{{ f.registro_id }}</td>
            <td>{{ usuario(f) }}<div class="text-secondary" style="font-size:.75rem">{{ f.usuario_bd }}</div></td>
            <td>
              <div v-for="c in cambios(f)" :key="c.k" class="text-break">
                <strong>{{ c.k }}:</strong>
                <template v-if="f.operacion === 'UPDATE'"> {{ fmtVal(c.antes) }} → {{ fmtVal(c.despues) }}</template>
                <template v-else> {{ fmtVal(f.operacion === 'INSERT' ? c.despues : c.antes) }}</template>
              </div>
            </td>
          </tr>
          <tr v-if="!datos.filas.length"><td colspan="6" class="text-center text-secondary py-4">No hay cambios registrados con estos filtros.</td></tr>
        </tbody>
      </table>
    </div>

    <div v-if="datos.paginas > 1" class="d-flex justify-content-center align-items-center gap-3 mt-3 no-print">
      <button class="btn btn-sm btn-outline-light" :disabled="datos.pagina <= 1" @click="cargar(datos.pagina - 1)">← Anterior</button>
      <span class="small text-secondary">Página {{ datos.pagina }} de {{ datos.paginas }}</span>
      <button class="btn btn-sm btn-outline-light" :disabled="datos.pagina >= datos.paginas" @click="cargar(datos.pagina + 1)">Siguiente →</button>
    </div>
  </div>
</template>
