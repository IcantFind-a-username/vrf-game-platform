import nextVitals from 'eslint-config-next/core-web-vitals';
import nextTypescript from 'eslint-config-next/typescript';

/** @type {import('eslint').Linter.Config[]} */
const config = [...nextVitals, ...nextTypescript];

export default config;
