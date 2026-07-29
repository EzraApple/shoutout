import { defineConfig } from "vite";
import { resolve } from "node:path";

export default defineConfig({
  build: {
    sourcemap: true,
    rollupOptions: {
      input: {
        main: resolve(__dirname, "index.html"),
        versionHistory: resolve(__dirname, "version-history/index.html"),
      },
    },
  },
});
