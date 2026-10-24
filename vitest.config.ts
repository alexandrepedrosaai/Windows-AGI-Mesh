import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";

export default defineConfig({

  resolve: {
    alias: {
      "@": fileURLToPath(
        new URL("./src", import.meta.url)
      )
    }
  },

  test: {

    globals: true,

    environment: "node",

    coverage: {

      provider: "v8",

      reporter: [
        "text",
        "html",
        "lcov"
      ],

      thresholds: {
        lines: 85,
        functions: 85,
        statements: 85,
        branches: 75
      }
    }
  }
});
