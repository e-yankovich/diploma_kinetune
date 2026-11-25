import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// In development the API is proxied to the backend (API_PROXY_TARGET, default
// http://localhost:8000). In production nginx serves the build and proxies /api.
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': process.env.API_PROXY_TARGET ?? 'http://localhost:8000',
    },
  },
});
