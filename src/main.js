import { createApp } from 'vue'
import { createRouter, createWebHashHistory } from 'vue-router'
import 'bootstrap/dist/css/bootstrap.min.css'
import 'bootstrap/dist/js/bootstrap.bundle.min.js'
import './style.css'
import App from './App.vue'
import { loadCatalog } from './store'

const routes = [
  { path: '/', component: () => import('./views/HomeView.vue') },
  { path: '/login', component: () => import('./views/LoginView.vue') },
  { path: '/autos', component: () => import('./views/CatalogView.vue') },
  { path: '/personalizar/:id', component: () => import('./views/CustomizeView.vue') },
  { path: '/rin/:id', component: () => import('./views/RimView.vue') },
  { path: '/llanta/:id', component: () => import('./views/TireView.vue') },
  { path: '/carrito', component: () => import('./views/CartView.vue') },
  { path: '/pago', component: () => import('./views/PaymentView.vue') },
  { path: '/admin', component: () => import('./views/AdminView.vue') },
]

const mount = () => createApp(App)
  .use(createRouter({ history: createWebHashHistory(), routes, scrollBehavior: () => ({ top: 0 }) }))
  .mount('#app')

// El catálogo viene de MySQL: la app se monta cuando ya está cargado.
loadCatalog().then(mount).catch(e => {
  const box = document.createElement('div')
  box.className = 'container py-5'
  box.innerHTML = '<div class="alert alert-danger"></div>'
  box.firstChild.textContent = `No se pudo cargar el catálogo (${e.message}). Verifica que MySQL y la API estén corriendo (npm run dev).`
  document.getElementById('app').replaceChildren(box)
})
