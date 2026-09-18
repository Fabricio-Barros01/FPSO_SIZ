# Dependências de terceiros vendorizadas

Servidas de `app/public/`, e não de um CDN, porque o programa empacotado com
PackageCompiler **abre sem internet**. Um script remoto não falha com erro: a figura
simplesmente não monta, e não há nada no console que o explique. É a mesma regra que
mantém `Genie.Assets` fora deste projeto — ver a nota no topo de `app/src/server.jl`.

| arquivo | origem | versão | licença |
|---|---|---|---|
| `three.module.min.js` | https://cdn.jsdelivr.net/npm/three@0.169.0/build/three.module.min.js | r169 | MIT — Copyright 2010-2024 Three.js Authors |
| `three-addons/controls/OrbitControls.js` | https://cdn.jsdelivr.net/npm/three@0.169.0/examples/jsm/controls/OrbitControls.js | r169 | MIT — idem |

A **versão é fixada** de propósito: o visor 3D depende da API de `OrbitControls`, que
mudou de forma entre versões de Three. Atualizar é trocar os dois arquivos juntos, pela
mesma versão, e conferir que o visor ainda monta.

Os caminhos `three` e `three/addons/` são resolvidos pelo mapa de importação declarado em
`app/public/casca.html`.

As fontes Barlow e Barlow Condensed (`app/public/ds/fonts/`) vêm do Google Fonts sob
**SIL Open Font License 1.1**, e estão aqui pelo mesmo motivo: o `@import` remoto do
design system foi substituído por `@font-face` locais.
