# Watchdog

Addon para **WoW Forever** (cliente 1.60.1, Interface `16001`). Versao **2.0.0**. Portugues e ingles.

Estatisticas por periodo (Total / Mes / Semana / Dia / Sessao):

- **PvE**: kills por mob, drops (com valor vendor/AH), ouro por kill, ordenacao por kills, valor, drop % e ultimos mortos.
- **PvP**: kills, mortes, K/D e honra.
- **EXP**: XP, XP/hora, tempo para upar, kills para upar e XP descansada.
- **Ouro**: ouro/hora e ouro da sessao como valor **farmado** (ouro dropado + quests + itens pelo valor no momento do loot; vender ou postar na AH nao muda).
- **Inventario** com valor de venda (maior entre vendor e AH, regra da %).
- **Leilao**: scan da AH, busca no catalogo e historico (compras, vendas, postados, expirados) com filtros.
- **Black list**: nomes PvE/PvP destacados na nameplate, alerta e macro de alvo.
- **Janela de loot** e barras flutuantes (ouro/h, XP/h, total da sessao, inventario).

## Instalacao

Extraia a pasta `Watchdog` em `Interface\AddOns` (o `Watchdog.toc` precisa ficar direto dentro de `Watchdog`).

```
git clone https://github.com/rsb1337/Watchdog.git "<pasta do WoW>\_forever_\Interface\AddOns\Watchdog"
```

## Comandos principais

- `/wd` ou botao do minimapa: abre/fecha a janela. `/wd ajuda` lista tudo.
- `/wd nova`: nova sessao. `/wd historico`, `/wd inventario`, `/wd relatorio`.
- `/wd bl` (ou `/wdbl`): **Black list compacta** (adicionar alvo, vistos, +M macro, A+ alerta, minimizar).
- `/wd blacklist`: aba completa da Black list.
- `/wd lootgoldbar`, `/wd goldbar`, `/wd expbar`, `/wd sgoldbar`, `/wd igoldbar`: janelas e barras flutuantes (tambem na aba Shortcuts).
- `/wd lang en|pt`: idioma.

## Black list e macro

Mire (ou escolha nos "vistos recentemente") e adicione. No Forever o jogador tem nome e sobrenome ("Kheza Mvp"); a macro "WD Alvo" tenta `Nome Sobrenome`, depois `Nome-Sobrenome` e por fim o primeiro nome. Marque UM nome com +M e arraste a macro para a barra.

## Regras de contagem

- **Kill PvE**: mob em que voce ou seu pet causaram dano e que morreu.
- **Drop**: contado ao abrir o loot do mob (inclui skin/pickpocket).
- **Kill PvP**: golpe final seu ou do pet em jogador inimigo. **Morte PvP**: morrer ate 15s depois de levar dano de jogador inimigo.
- **Sessao**: comeca a cada login; `/reload` mantem a sessao.
- Dados por personagem em `WatchdogCharDB`; leilao e configuracoes na conta em `WatchdogDB`.

## Historico de versoes

Veja o [CHANGELOG](CHANGELOG.md).
