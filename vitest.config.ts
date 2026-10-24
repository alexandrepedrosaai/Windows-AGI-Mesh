import { defineConfig } from "vitest/config";
import * as path from "node:path";

export default defineConfig({

  resolve: {
    alias: {
      "@": path.resolve(__dirname, "src")
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
