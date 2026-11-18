# Changelog

## 1.5.0 (Beta)

### Novo: Assistente
- Aviso grande (estilo boss) quando buffs, venenos ou encantamentos de arma estao para acabar.
- Timer de crowd control sobre a cabeca do alvo, com as skills da sua classe e estimativa de diminishing returns contra jogadores.
- Lembrete de reparo, comida e consumiveis ao chegar em cidades/locais com vendor, craft ou leilao.
- Lista de consumiveis por classe, com preset inicial, adicao por Ctrl+Alt+clique ou digitando (com autocompletar).
- Aba de alertas de drop/mob raro nas configuracoes (mesmas opcoes do `/wd alerts`).
- Menu de configuracoes (`/wd config`) e janela de comandos (`/wd commands`) no estilo do Watchdog.

### Correcoes
- Aviso nao some mais quando a escala fica abaixo de 100% e nao trava mais com a interface oculta.
- Bordas de 1 pixel desenhadas em pixel real da tela (botoes, cartoes, janelas).
- Janelas abertas ao mesmo tempo nao se misturam mais (a clicada sobe inteira).
- Botao do minimapa fica na borda do anel; botoes da lateral sobem um pouco.
- Comando de alertas em ingles: `/wd alerts` (`/wd alertas` continua valendo).

## 1.4.4
- Corrigido o erro de "secret string value" dentro de dungeons (nomes de unidade protegidos).

## 1.4.3
- Removido o registro de `COMBAT_LOG_EVENT_UNFILTERED`, que causava o popup "bloqueado de uma acao disponivel apenas para a UI da Blizzard".
- Mortes PvP passam a ser contadas sem o combat log (golpe recente de jogador inimigo).

## 1.4.2
- Eventos de chat que nao existem neste cliente viraram opcionais e nao mostram mais a mensagem vermelha de "nao consegui registrar o evento".

## 1.4.1
- Protecao ao ajustar variaveis do jogo (CVars) durante combate.

## 1.4.0
- Correcao de mortes PvP, idiomas EN/PT-BR, barras flutuantes e lista premium.

## 1.0.0
- Kills PvE/PvP, drops por mob, honra e EXP/hora.
