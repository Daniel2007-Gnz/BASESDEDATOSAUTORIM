<script setup>
import { ref, watch, onMounted } from 'vue'
import { store, fmt, adminLogin, adminLogout } from '../store'
import { api } from '../api'
import TablasCrud from '../components/admin/TablasCrud.vue'
import Reportes from '../components/admin/Reportes.vue'
import AuditoriaReport from '../components/admin/AuditoriaReport.vue'

const f = ref({ email: '', password: '', code: '' })
const error = ref('')
const resumen = ref({ pedidos: 0, clientes: 0 })
const pedidos = ref([])
const tab = ref('pedidos') // pedidos | reportes | tablas | auditoria

async function cargar() {
  try {
    resumen.value = await api('/admin/resumen', { admin: true })
    pedidos.value = await api('/admin/pedidos', { admin: true })
  } catch (e) {
    if (e.status === 401 || e.status === 403) adminLogout()
    else error.value = e.message
  }
}
async function login() {
  error.value = ''
  try {
    adminLogin((await api('/auth/admin-login', { method: 'POST', body: f.value })).token)
    f.value.password = f.value.code = ''
    await cargar()
  } catch (e) { error.value = e.message }
}
onMounted(() => { if (store.admin) cargar() })
watch(tab, t => { if (t === 'pedidos') cargar() }) // refresca el resumen tras editar tablas
</script>

<template>
  <div v-if="!store.admin" class="container py-5" style="max-width:440px">
    <div class="panel p-4">
      <h1 class="h3">Acceso de personal</h1>
      <p class="text-secondary small">Solo para administradores de AutoRim.</p>
      <div v-if="error" class="alert alert-danger py-2 small">{{ error }}</div>
      <form class="d-grid gap-3" @submit.prevent="login">
        <div><label class="form-label small" for="ae">Correo</label><input id="ae" v-model="f.email" type="email" class="form-control" required /></div>
        <div><label class="form-label small" for="ap">Contraseña</label><input id="ap" v-model="f.password" type="password" class="form-control" required /></div>
        <div><label class="form-label small" for="ac">Código de acceso</label><input id="ac" v-model="f.code" type="password" class="form-control" required /></div>
        <button class="btn btn-red">Ingresar como administrador</button>
      </form>
    </div>
  </div>

  <div v-else class="container py-5">
    <div class="d-flex justify-content-between align-items-center mb-4">
      <h1 class="mb-0">Panel de administración</h1>
      <button class="btn btn-outline-light btn-sm" @click="adminLogout">Cerrar sesión</button>
    </div>
    <div class="nav nav-pills mb-4 gap-2 no-print">
      <button class="nav-link" :class="{ active: tab === 'pedidos' }" @click="tab = 'pedidos'">Pedidos</button>
      <button class="nav-link" :class="{ active: tab === 'reportes' }" @click="tab = 'reportes'">Reportes</button>
      <button class="nav-link" :class="{ active: tab === 'tablas' }" @click="tab = 'tablas'">Tablas (CRUD)</button>
      <button class="nav-link" :class="{ active: tab === 'auditoria' }" @click="tab = 'auditoria'">Auditoría</button>
    </div>
    <template v-if="tab === 'pedidos'">
    <div class="row g-3 mb-4">
      <div class="col-6 col-md-3"><div class="panel p-3"><div class="text-secondary small">Pedidos</div><div class="fs-3">{{ resumen.pedidos }}</div></div></div>
      <div class="col-6 col-md-3"><div class="panel p-3"><div class="text-secondary small">Clientes</div><div class="fs-3">{{ resumen.clientes }}</div></div></div>
    </div>
    <div class="panel p-3 table-responsive">
      <table class="table align-middle mb-0">
        <thead><tr><th>Pedido</th><th>Fecha</th><th>Cliente</th><th>Productos</th><th>Estado</th><th class="text-end">Total</th></tr></thead>
        <tbody>
          <tr v-for="o in pedidos" :key="o.pedido">
            <td>{{ o.pedido }}</td><td>{{ new Date(o.fecha).toLocaleString('es-CO') }}</td><td>{{ o.cliente }}</td>
            <td class="small text-secondary">{{ o.productos }}</td><td class="text-capitalize">{{ o.estado }}</td><td class="text-end">{{ fmt(o.total) }}</td>
          </tr>
          <tr v-if="!pedidos.length"><td colspan="6" class="text-center text-secondary py-4">Todavía no hay pedidos.</td></tr>
        </tbody>
      </table>
    </div>
    </template>
    <Reportes v-else-if="tab === 'reportes'" />
    <TablasCrud v-else-if="tab === 'tablas'" />
    <AuditoriaReport v-else />
  </div>
</template>
