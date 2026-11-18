# Watchdog

Addon para **WoW Forever** (cliente 1.60.1, Interface `16001`).

Registra, com filtro por periodo (Total / Mes / Semana / Dia / Sessao):

- **PvE**: kills por mob e, ao clicar no mob, quantas vezes cada item dropou.
- **PvP**: kills (golpe final), mortes para jogadores, K/D e honra ganha.
- **EXP**: XP ganha, XP/hora, tempo para upar, kills para upar e XP descansada.

## Assistente (1.5.0)

- Aviso grande (estilo boss) quando buffs, venenos ou encantamentos de arma estao para acabar.
- Timer de crowd control sobre a cabeca do alvo, so com as skills da sua classe, com estimativa de diminishing returns.
- Lembretes de reparo, comida e consumiveis ao chegar em cidades/locais com vendor, craft ou leilao.
- Lista de consumiveis por classe (preset inicial), com Ctrl+Alt+clique no item ou digitando, com autocompletar.
- Alertas de drop/mob raro configuraveis.
- Menu de configuracoes (`/wd config`) e janela de comandos (`/wd commands`).

## Instalacao

Clone ou extraia esta pasta em `Interface\AddOns\Watchdog` (o arquivo `Watchdog.toc` precisa ficar direto dentro de `Watchdog`).

```
git clone https://github.com/rsb1337/Watchdog.git "<pasta do WoW>\_forever_\Interface\AddOns\Watchdog"
```

## Uso

- Botao no minimapa ou `/wd` abre/fecha a janela.
- `/wd nova` inicia uma nova sessao.
- `/wd minimapa` mostra/esconde o botao do minimapa.
- `/wd ajuda` lista os comandos.

## Regras de contagem

- **Kill PvE**: mob em que voce ou seu pet causaram dano e que morreu.
- **Drop**: contado ao abrir o loot do mob (inclui skin/pickpocket), mesmo que o item nao seja pego.
- **Kill PvP**: golpe final seu ou do pet em jogador inimigo.
- **Morte PvP**: morrer ate 15s depois de levar dano de jogador inimigo.
- **Sessao**: comeca a cada login; `/reload` mantem a sessao.
- Dados salvos por personagem (`WatchdogCharDB`).

## Status

Versao 1.5.0 (Beta). Dados de contagem e Assistente funcionam no WoW Forever; o Assistente ainda esta em teste.
