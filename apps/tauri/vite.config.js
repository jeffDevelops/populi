import { defineConfig } from "vite";
import { sveltekit } from "@sveltejs/kit/vite";

const host = process.env.TAURI_DEV_HOST;

// Get port configuration from environment variables or use defaults
const serverPort = parseInt(process.env.VITE_SERVER_PORT || "1420", 10);
const hmrPort = parseInt(process.env.VITE_HMR_PORT || "1421", 10);
const instanceId = process.env.VITE_INSTANCE_ID || "1";

console.log(
  `Starting Vite instance ${instanceId} on server port: ${serverPort}, HMR port: ${hmrPort}`
);

// https://vite.dev/config/
export default defineConfig(async () => ({
  plugins: [sveltekit()],

  // Vite options tailored for Tauri development and only applied in `tauri dev` or `tauri build`
  //
  // 1. prevent Vite from obscuring rust errors
  clearScreen: false,
  // 2. configure port dynamically based on environment variables
  server: {
    port: serverPort,
    strictPort: true,
    host: host || "0.0.0.0",
    hmr: host
      ? {
          protocol: "ws",
          host,
          port: hmrPort,
        }
      : {
          port: hmrPort,
        },
    watch: {
      // 3. tell Vite to ignore watching `src-tauri`
      ignored: ["**/src-tauri/**"],
    },
  },
}));
