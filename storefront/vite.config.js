import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite' // <--- Thêm dòng này

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    tailwindcss(), // <--- Thêm dòng này vào danh sách plugins
  ],
  build: {
    sourcemap: false,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes('node_modules')) return undefined;
          if (id.includes('@supabase/')) return 'vendor-supabase';
          if (id.includes('framer-motion') || id.includes('motion-dom') || id.includes('motion-utils')) return 'vendor-motion';
          if (id.includes('react-icons')) return 'vendor-icons';
          if (id.includes('axios')) return 'vendor-http';
          if (id.includes('/react/') || id.includes('/react-dom/') || id.includes('react-router') || id.includes('react-helmet')) return 'vendor-react';
          return undefined;
        },
      },
    },
  },
})
