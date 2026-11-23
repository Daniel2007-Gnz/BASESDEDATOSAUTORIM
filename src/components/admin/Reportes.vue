<script setup>
import { ref, computed, onMounted } from 'vue'
import { api } from '../../api'
import { fmt, adminLogout } from '../../store'

const MESES = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic']
const TIPOS = { kit: 'Kit', rines: 'Rines', llantas: 'Llantas' }
const datos = ref(null)
const anio = ref(new Date().getFullYear())
const producto = ref('')
const error = ref('')

async function cargar() {
  error.value = ''
  try { datos.value = await api(`/admin/estadisticas?anio=${anio.value}`, { admin: true }) }
  catch (e) { if (e.status === 401 || e.status === 403) adminLogout(); else error.value = e.message }
}
onMounted(cargar)

const nombres = computed(() => [...new Set((datos.value?.productos ?? []).map(p => p.producto))].sort())
const filas = computed(() => MESES.map((nombre, i) => {
  const mes = `${anio.value}-${String(i + 1).padStart(2, '0')}`
  if (!producto.value) {
    const m = datos.value?.mensual.find(x => x.mes === mes)
    return { nombre, pedidos: m?.pedidos ?? 0, compradores: m?.compradores ?? 0, unidades: m?.unidades ?? 0, ingresos: m?.ingresos ?? 0 }
  }
  const p = datos.value?.productos.find(x => x.mes === mes && x.producto === producto.value)
  return { nombre, pedidos: null, compradores: null, unidades: p?.unidades ?? 0, ingresos: p?.ingresos ?? 0 }
}))
const maxUnidades = computed(() => Math.max(1, ...filas.value.map(f => f.unidades)))
const ranking = computed(() => {
  const m = new Map()
  for (const p of datos.value?.productos ?? []) {
    const k = `${p.tipo}|${p.producto}`
    const r = m.get(k) ?? { tipo: p.tipo, producto: p.producto, unidades: 0, ingresos: 0 }
    r.unidades += p.unidades; r.ingresos += p.ingresos
    m.set(k, r)
  }
  return [...m.values()].sort((a, b) => b.unidades - a.unidades)
})
</script>

<template>
  <div v-if="error" class="alert alert-danger py-2 small">{{ error }}</div>
  <div v-else-if="!datos" class="text-secondary">Cargando reportes…</div>
  <template v-else>
    <div class="d-flex align-items-center gap-2 mb-3">
      <label class="small text-secondary" for="ra">Año</label>
      <select id="ra" v-model.number="anio" class="form-select form-select-sm w-auto" @change="producto = ''; cargar()">
        <option v-for="a in [...new Set([anio, ...datos.anios])]" :key="a" :value="a">{{ a }}</option>
      </select>
    </div>

    <div class="row g-3 mb-4">
      <div class="col-6 col-md-3"><div class="panel p-3"><div class="text-secondary small">Clientes registrados</div><div class="fs-3">{{ datos.usuarios.clientes }}</div></div></div>
      <div class="col-6 col-md-3"><div class="panel p-3"><div class="text-secondary small">Compradores (con compra)</div><div class="fs-3">{{ datos.usuarios.compradores }}</div></div></div>
      <div class="col-6 col-md-3"><div class="panel p-3"><div class="text-secondary small">Clientes sin compras</div><div class="fs-3">{{ datos.usuarios.sin_compras }}</div></div></div>
      <div class="col-6 col-md-3"><div class="panel p-3"><div class="text-secondary small">Administradores</div><div class="fs-3">{{ datos.usuarios.administradores }}</div></div></div>
      <div class="col-6 col-md-3"><div class="panel p-3"><div class="text-secondary small">Pedidos vendidos (total)</div><div class="fs-3">{{ datos.totales.pedidos }}</div></div></div>
      <div class="col-6 col-md-3"><div class="panel p-3"><div class="text-secondary small">Unidades {{ datos.anio }}</div><div class="fs-3">{{ datos.totales.unidades }}</div></div></div>
      <div class="col-12 col-md-6"><div class="panel p-3"><div class="text-secondary small">Ingresos por productos {{ datos.anio }} (sin envío)</div><div class="fs-3">{{ fmt(datos.totales.ingresos) }}</div></div></div>
    </div>
    <p class="small text-secondary">Se cuentan pedidos en estado pagado, enviado o entregado. AutoRim vende directamente: no existe el rol «vendedor», solo cliente y administrador.</p>

    <div class="panel p-3 mb-4">
      <h2 class="h6">Cuentas con rol administrador</h2>
      <ul class="mb-0 small"><li v-for="a in datos.admins" :key="a.id">{{ a.email }} <span class="text-secondary">· creada {{ a.creado }}</span></li></ul>
    </div>

    <div class="panel p-3 mb-4 table-responsive">
      <div class="d-flex flex-wrap justify-content-between align-items-center gap-2 mb-2">
        <h2 class="h6 mb-0">Ventas por mes {{ datos.anio }}</h2>
        <select v-model="producto" class="form-select form-select-sm w-auto" aria-label="Producto">
          <option value="">Todos los productos</option>
          <option v-for="n in nombres" :key="n" :value="n">{{ n }}</option>
        </select>
      </div>
      <table class="table align-middle mb-0">
        <thead><tr><th>Mes</th><th class="text-end">Pedidos</th><th class="text-end">Compradores</th><th class="text-end">Unidades</th><th style="width:25%"></th><th class="text-end">Ingresos</th></tr></thead>
        <tbody>
          <tr v-for="f in filas" :key="f.nombre">
            <td>{{ f.nombre }}</td><td class="text-end">{{ f.pedidos ?? '—' }}</td><td class="text-end">{{ f.compradores ?? '—' }}</td><td class="text-end">{{ f.unidades }}</td>
            <td><div class="bg-danger rounded" :style="{ height: '8px', width: (f.unidades / maxUnidades * 100) + '%' }"></div></td>
            <td class="text-end">{{ fmt(f.ingresos) }}</td>
          </tr>
        </tbody>
      </table>
      <p class="small text-secondary mt-2 mb-0">Rines y llantas se venden en sets de 4; cada unidad es un set.</p>
    </div>

    <div class="panel p-3 table-responsive">
      <h2 class="h6">Productos más vendidos {{ datos.anio }}</h2>
      <table class="table align-middle mb-0">
        <thead><tr><th>Producto</th><th>Tipo</th><th class="text-end">Unidades</th><th class="text-end">Ingresos</th></tr></thead>
        <tbody>
          <tr v-for="r in ranking" :key="r.tipo + r.producto" role="button" @click="producto = r.producto">
            <td>{{ r.producto }}</td><td>{{ TIPOS[r.tipo] ?? r.tipo }}</td><td class="text-end">{{ r.unidades }}</td><td class="text-end">{{ fmt(r.ingresos) }}</td>
          </tr>
          <tr v-if="!ranking.length"><td colspan="4" class="text-center text-secondary py-4">Sin ventas en {{ datos.anio }}.</td></tr>
        </tbody>
      </table>
    </div>
  </template>
</template>
