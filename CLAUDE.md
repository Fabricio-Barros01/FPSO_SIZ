## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Publicação no GitHub

Remote oficial do projeto:

```sh
git remote add origin https://github.com/Fabricio-Barros01/FPSO_SIZ.git
git branch -M main
git push -u origin main
```

Ressalvas, porque estes três comandos não são inócuos no estado atual do repositório:

- `git branch -M main` **renomeia à força a branch em que você estiver**. Já existe uma
  branch `main` neste repositório, e rodá-lo a partir de uma branch de trabalho (por
  exemplo `pinch-nucleo-kemp`) sobrescreve a `main` existente e apaga o histórico dela
  como referência nomeada. Antes de rodá-lo, confirme em qual branch está
  (`git branch --show-current`) e se é mesmo a `main` que você quer publicar.
- `git push` publica o repositório num host externo. Depois de publicado, o conteúdo
  pode ficar em cache ou indexado mesmo que seja apagado. `References/` (49 MB de PDFs
  de terceiros sob direito autoral) está em `.gitignore` e **não** vai junto — o que
  também significa que quem clonar o repositório não conseguirá conferir as citações de
  página sem obter a bibliografia por conta própria. `docs/validacao/` VAI junto, de
  propósito: é onde as citações ficam registradas, e sem ele o repositório publicaria as
  contas sem a auditoria delas.
- `graphify-out/` é artefato gerado e está ignorado, mas **107 arquivos dele já estavam
  versionados** antes disso. `.gitignore` não desversiona o que já entrou: é preciso
  `git rm -r --cached graphify-out` uma vez (não apaga nada do disco).
- O projeto é MIT (arquivo `LICENSE`), Copyright (c) 2026 Fabricio Barros.
