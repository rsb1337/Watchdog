# Changelog

## 1.6.18

### Novo
- Black list: seletor da tecla de alvo direto no painel. Clique no botao e aperte a tecla (com Alt/Ctrl/Shift se quiser) ou um botao do mouse; botoes Padrao (CapsLock) e Off; indicador mostra se a tecla esta ativa, nao aceita ou aguardando o fim do combate.

## 1.6.17

### Correcoes
- Tecla de alvo da Black list: nao seleciona mais mobs mortos fora de combate. Ela escolhe so alvos vivos da lista entre as plaquinhas e, apertando de novo, passa para o proximo. Em combate usa o comando por nome, que limpa o alvo se ele estiver morto.

## 1.6.16

### Novo
- Tecla de alvo da Black list: o CapsLock (configuravel) seleciona como alvo o primeiro nome da Black list que estiver por perto, PvE e PvP. O addon monta o comando sozinho e o atualiza a cada nome adicionado ou removido. Mudar a tecla: /wd alvo TECLA; desligar: /wd alvo off.

## 1.6.15

### Correcoes
- Leilao (AH): corrigido o valor do Auction house que continuava em 0 com a API nova de leilao. A listagem recem postada nao e mais apagada por uma leitura atrasada da lista do jogo, e recolher itens cancelados no correio nao apaga mais as outras listagens.

## 1.6.14

### Correcoes
- Leilao (AH): o addon agora le a lista real dos seus leiloes ativos ao abrir a casa de leiloes, alem de capturar o preco na hora de postar. Corrige o quadro Auction house que ficava em 0.
- Registro de diagnostico dos eventos/API de leilao do cliente (WatchdogDB.ahDiag) para ajustar a captura.

## 1.6.13

### Mudancas
- Botao Report removido da aba PvE.
- Botao Back agora fica na mesma linha do segundo menu (24h / 7 days / 30 days), longe do Active session.
- Fonte dos botoes New session / Commands reduzida para nao encostar nas bordas.
- Ouro da sessao: o quadro Inventory foi removido; o primeiro quadro agora e "Collected gold" (gold puro + valor de vendor dos itens coletados). Ficam 3 quadros: Collected gold, Auction house e Probable.
- Tempo fora do grind: o quadro Crafting foi removido (o tempo de craft entra em "Other"); a linha ficou com 3 colunas.

## 1.6.12

### Mudancas
- Botoes de selecao (abas do PvE, periodos, abas de Alertas): so o selecionado fica com borda; os outros ficam sem borda.
- Cores dos detalhes da sessao: tempo e mobs em branco; K/D do PvP vermelho abaixo de 1 e verde a partir de 1; tudo de EXP e quests em roxo; tudo de ouro em amarelo; grind verde e fora do grind vermelho.
- O ouro da sessao (rodape "Session", barra /wd sgoldbar, ouro por hora e lista do historico) agora usa o mesmo valor do Gold provavel: puro + inventario + AH.

## 1.6.11

### Mudancas
- Ouro da sessao agora mostra 4 valores: Gold puro (moedas recebidas), Inventario (valor de vendor dos itens), Leilao/AH (preco que voce colocou nos itens listados) e Provavel (soma dos tres). O "Gold gasto" foi removido.
- O addon registra o preco de cada item que voce lista na AH; a listagem sai da conta quando vende (dinheiro chega pelo correio), cancela ou expira.

## 1.6.10

### Melhorias
- Aviso de consumiveis: cada item em falta ganha o seu proprio cartao, um embaixo do outro, com o icone e a quantidade do respectivo item. Se o item nao tiver icone, mostra o emblema do Watchdog.

## 1.6.9

### Correcoes
- Timer de CC: quando o alvo some da tela ou fica longe (sem nameplate), o icone nao aparece mais no meio da tela. Ele so e mostrado sobre a cabeca do alvo; o tempo continua correndo e o icone volta quando a nameplate reaparece.

## 1.6.8

### Correcoes
- O aviso de consumiveis agora mostra o icone do item em falta (antes sempre o icone do veneno).

## 1.6.7

### Correcoes
- Aviso de consumiveis: agora so avisa quando a quantidade esta ABAIXO do minimo definido (antes avisava tambem com a quantidade exatamente igual, ex.: 10/10).
- Textos das configuracoes atualizados para explicar a regra.

## 1.6.6

### Correcoes
- CC de alvo unico (Sap, Polymorph, Shackle Undead, Mind Control, Banish, Seduction, Hibernate, Scare Beast): usar em outro alvo remove o aviso do anterior, como acontece no jogo.

## 1.6.5

### Correcoes
- Alertas: as listas de buffs e de consumiveis ganharam "... e mais N (clique para ver todos)", que abre uma janela com a lista completa, rolagem e botao de remover. Nada fica oculto.

## 1.6.4

### Novo
- Menu lateral novo: PvE, PvP, Alertas e Black list. A janela ficou mais larga.
- Black list com colunas PvE/PvP e nomes vistos recentemente.
- Assistente de primeiro uso (wizard) apos instalar.
- Historico clicavel: cada sessao abre seus detalhes (tempo, EXP por mob/quest, mobs, K/D no PvP, quests, tempo fora de grind por tipo).
- Janelas de 24h, 7d e 30d no historico, contando o tempo offline.
- Botao "Sessao ativa" ao lado do cronometro.
- Ouro adquirido e ouro gasto (moedas + vendas + valor de vendor da bag/banco, com itens em transito na AH/correio).
- Primeira abertura apos o login vai direto para a aba EXP; EXP mostra apenas a sessao.

### Correcoes
- Tempo offline das sessoes passadas agora e contabilizado.
- Avisos de consumivel nao disparam mais com nomes ainda nao carregados.
- Botoes da aba Alertas nao saem mais da janela.


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
