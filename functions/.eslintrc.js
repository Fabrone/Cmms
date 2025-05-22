module.exports = {
  env: {
    node: true,
    es2021: true
  },
  extends: "eslint:recommended",
  parserOptions: {
    ecmaVersion: 12,
    sourceType: "module"
  },
  rules: {
    quotes: ["error", "double"],
    "object-curly-spacing": ["error", "always"],
    "max-len": ["error", { code: 100 }],
    "eol-last": ["error", "always"]
  }
};
