# Changelog

## 1.8.4

### Corrigido
- Erro de Lua repetido ao abrir a lista do Sort (UI.lua: attempt to call a nil value, contador subindo sem parar): a lista usava uma funcao que o cliente nao tem (MouseIsOver) dentro de um OnUpdate. Agora usa o metodo do proprio frame (IsMouseOver), com protecao: se algo falhar, o fechamento automatico e desligado em vez de repetir o erro a cada quadro.

## 1.8.3

### Corrigido
- Lista do botao Sort (PvE): as opcoes eram mostradas mas nao respondiam ao clique. A lista foi refeita sem camada especial nem fundo de captura: fica sobre a janela, aceita o clique em cada opcao e fecha sozinha quando o mouse sai dela.

## 1.8.2

### Corrigido
- Gold da sessao zerando (ex.: ao skinnar): a deteccao de itens soulbound por tooltip podia errar quando o jogo ainda nao tinha carregado o tooltip (inicio da sessao, /reload, loot), valendo o item pelo preco da AH no ponto de partida e pelo vendor depois, o que criava uma queda falsa no valor das bolsas. Agora usa primeiro a informacao direta do jogo (C_Item.IsBound), so depois o tooltip, e quando nao ha certeza o valor das bolsas nao e atualizado (tenta de novo em 2s, ate 4 vezes) em vez de chutar. Itens ja vistos como soulbound ficam assim por 2 minutos.
- Depois de atualizar, inicie uma "New session": o ponto de partida da sessao atual pode ter sido gravado com o valor errado.

## 1.8.1

### Novo
- Aba PvE > Mobs: nova ordenacao "Latest kills" (ultimos mortos de cima para baixo: o mob que voce matou por ultimo fica no topo).
- O botao Sort agora abre uma lista com todas as opcoes (Kills, Value, $/kill, Drop %, Latest kills); basta clicar na que quiser, em vez de trocar uma a uma sem saber a proxima. A opcao atual fica marcada e a lista fecha ao escolher ou clicar fora.
- Os mobs passam a guardar o horario do ultimo abate (mobs mortos antes desta versao aparecem no fim da lista "Latest kills" ate serem mortos de novo).

## 1.8.0

### Novo
- Aba Leilao: passar o mouse sobre um item mostra o tooltip normal do jogo (stats, requisitos, texto de uso, mais as linhas dos outros addons e a linha "Watchdog AH"). Se o item ainda nao estiver no cache do jogo, o tooltip se completa sozinho em instantes. As linhas ganharam destaque ao passar o mouse e a roda do mouse continua rolando a lista.

## 1.7.17

### Corrigido
- Precos errados no scan da AH: o jogo entrega a lista de leiloes aos poucos (ela crescia de 58 mil para 66 mil+ durante a leitura) e o addon lia no meio do download, pegando so uma parte dos leiloes. Agora ele SEMPRE espera a quantidade parar de crescer (4s seguidos iguais, ate 4 min) antes de ler, inclusive quando usa a lista que o jogo ja tinha em memoria. Removido o recomeco automatico durante a leitura.
- O painel mostra "Recebendo a lista... N leiloes" enquanto espera e o scan nao falha por tempo enquanto a lista ainda esta chegando.
- Depois de atualizar, refaca o scan: os precos gravados pelos scans anteriores podem estar incompletos.

## 1.7.16

### Alterado
- Aba Atalhos: removida a secao "Windows and actions" (Report, Commands list, Settings, New session, Max nameplate range, Welcome guide) e o botao Borders (os contornos ficam so no inventario). Sobraram os botoes de ligar/desligar: gold/hour, XP/hour, session gold, inventory value e Minimap icon.

## 1.7.15

### Corrigido
- Scan da AH incompleto (ex.: Runecloth gravado com 2.510 unidades a 12s80c quando a AH tinha 16.723 a 6s06c): o addon agora so comeca a ler quando a quantidade de leiloes para de crescer (3s seguidos iguais), le em blocos maiores e recomeca se a lista mudar durante a leitura.
- Diagnostico menos poluido: eventos repetidos da AH deixam de lotar o log; ficam registrados o tamanho da lista estabilizada e as estatisticas do scan.

## 1.7.14

### Novo
- Tooltip "Watchdog AH": segurando Shift com o mouse sobre uma pilha, mostra o valor da pilha inteira (ex.: x20 = 20 vezes o preco unitario); soltando o Shift volta ao preco individual. O tooltip se atualiza na hora, sem mexer o mouse.

## 1.7.13

### Alterado
- Organizar por cor ficou muito mais rapido: faz varias trocas por quadro (esperando so o servidor liberar os slots) e, no fim, confere o resultado e refaz o que sobrou.

## 1.7.12

### Corrigido
- Itens de quest que tem preco de vendor ou aparecem na Casa de Leiloes (ex.: Evil Bat Eye) deixaram de ficar apagados. Agora so ficam apagados os que nao valem nada em lugar nenhum (sem vendor e sem AH).

## 1.7.11

### Novo
- Botao "Organizar por cor" ao lado da moeda na janela da bolsa do WoW: reorganiza as bolsas colocando primeiro os itens apagados (sem venda), depois os da Casa de Leiloes e por ultimo os do vendor. Faz um movimento por vez, para se em combate e nao mistura pilhas. Bolsas especiais (municao, profissao) nao sao mexidas.

### Corrigido
- Item que vira soulbound ao ser equipado (bind ao equipar) agora e detectado como soulbound pelo tooltip, entao deixa de aparecer como item de AH (laranja) e passa a valer so o vendor.

## 1.7.10

### Corrigido
- Scan da AH: quando a casa de leiloes nao envia uma lista nova (ela limita a frequencia dos scans), o addon agora le a lista que o jogo ja tinha em memoria apos 15s, em vez de falhar so no fim dos 90s.
- Mensagem de erro de "sem resposta" encurtada para caber no painel sem ser cortada.

## 1.7.9

### Alterado
- Painel do scan da AH redesenhado no estilo Watchdog: fundo e bordas do addon, faixa vermelha, emblema, titulo "WATCHDOG AH SCAN", botao SCAN plano com borda vermelha (no lugar do botao padrao do WoW), texto de status em linha propria sem invadir o botao e barra de progresso fina.

## 1.7.8

### Corrigido
- Tooltip "Watchdog AH": o preco agora aparece com os icones de ouro, prata e cobre (antes saia so o numero, ex.: "33").

## 1.7.7

### Corrigido
- Aba Leilao: itens que apareciam como "Item #1234" (e por isso nao eram achados na busca) agora tem o nome carregado em segundo plano, aos poucos, assim que o jogo os envia. A lista e a busca se atualizam sozinhas.
- Scan: ao terminar, mostra no chat quantos leiloes foram lidos, quantos tinham preco de compra imediata e quantos foram ignorados (so lance), e grava isso no diagnostico.

## 1.7.6

### Corrigido
- Scan da AH: o botao agora fica num painel preso na janela da AH do WoW (acima do canto esquerdo, arrastavel; se o cliente nao expuser a janela, aparece solto na tela). Removido o botao Scan da aba Leilao do addon.
- Barra de progresso do scan: pedindo a lista, aguardando (segundos), recebendo, lendo X / total (%), concluido com itens e tempo, ou erro em vermelho (AH ocupada, sem resposta em 90s, sem API).
- Espera a lista "assentar" antes de ler (ela pode chegar em varios eventos) e registra cada etapa em WatchdogDB.ahDiag para diagnostico.

## 1.7.5

### Alterado
- Itens soulbound (e que sao bind ao pegar) sempre valem o preco de vendor, pois nao podem ir para a AH. BoE entra nas duas regras e vale o maior.
- Contornos: laranja = vale mais na AH, azul = vale mais no vendor (padrao; as cores continuam configuraveis).
- Com os contornos ligados, itens que nao podem ser vendidos de nenhum jeito (quest, sem valor de vendor e sem AH) ficam apagados, nas bolsas do jogo e na aba Inventario.

## 1.7.4

### Novo
- Botao liga/desliga dos contornos direto na bolsa do jogo: um icone de moeda aparece acima da janela da bolsa aberta (borda verde = ligado, cinza = desligado).

## 1.7.3

### Novo
- Scan da casa de leiloes: botao "Watchdog: Scan" na janela da AH (e na aba Leilao) le o menor preco de cada item. Tag "Watchdog AH" no tooltip, abaixo do vendor, com a idade do scan.
- Aba "Leilao": busca no catalogo do ultimo scan (consulta de qualquer lugar), ordenacao por nome/preco, engrenagem com as configuracoes.
- Valor dos itens agora usa o maior entre vendor e AH. Se o vendor for >= X% do preco da AH (padrao 80%, ajustavel e desativavel na engrenagem), vale o vendor. Vale para ouro/hora, inventario, mobs e resumo da sessao; o resumo separa itens valorizados por vendor e por AH.
- Contornos coloridos nos itens (prata = vale mais no vendor, dourado = vale mais na AH; cores escolhidas na engrenagem), com botao liga/desliga na aba Inventario, nos Atalhos e em /wd bordas. Tambem tenta contornar os itens das bolsas do jogo.
- Comandos: /wd ah, /wd scan, /wd bordas.

## 1.7.2

### Novo
- Nova aba "Atalhos" no menu lateral: botoes para o que antes era so comando. Barras (ouro/hora, XP/hora, ouro da sessao, valor do inventario) e icone do minimapa com marcacao verde ON/OFF; botoes para abrir Relatorio, Lista de comandos, Configuracoes, Nova sessao, Alcance das plaquinhas e Guia de boas-vindas.

## 1.7.1

### Novo
- Alerts: escolha do som de cada tipo de alerta (mob raro / A+, drop raro, raro morto, avisos grandes) entre sons do WoW, com botao Testar. Padrao continua o aviso de raide. Clique troca para o proximo (botao direito volta), e toca o som na hora. Se o cliente nao tiver o som, toca o padrao.

## 1.7.0

Versao de consolidacao (sem mudancas de codigo alem do numero). Reune as novidades da serie 1.6.x:
- Black list com macro "WD Alvo" (um mob por vez, botao "+M") e alerta por mob ("A+").
- Ouro: coletado / leilao / provavel; tela de sessoes e historico reorganizadas.
- Avisos de consumiveis com icone proprio por item, Sap em um unico alvo, icones de CC na plaquinha.

## 1.6.26

### Novo
- Black list: botao "A+" ao lado do "+M" em cada nome. Com "A" ligado, o mob da lista dispara um aviso (como mob raro) quando aparece por perto, uma vez por mob. Pode marcar varios.

## 1.6.25

### Alterado
- Icone da macro "WD Alvo": agora o olho de aguia (Eagle Eye) do jogo. Aplicado uma vez quando o icone do addon muda; depois, trocar em /macro vale.

## 1.6.24

### Alterado
- Macro "WD Alvo": so um mob por vez (marcar +M em um tira o anterior).
- Icone da macro: o jogo nao aceita imagem do addon, entao usa um icone padrao do jogo (so aplicado quando a macro ainda esta com "?"; trocar manualmente em /macro vale).

## 1.6.23

### Alterado
- Black list: removidos a tecla de alvo (F7/Reset/Off) e o botao seguro; fica so o botao "Pegar macro".
- Cada nome da lista ganhou um botao "+M": so os marcados entram na macro "WD Alvo" (que se atualiza sozinha fora de combate). Remover o nome da lista tira a marca.

## 1.6.22

### Novo
- Macro "WD Alvo": usa o emblema do Watchdog como icone (se o jogo nao aceitar, cai num icone padrao de olho).

## 1.6.21

### Novo
- Black list: botao "Pegar macro" cria a macro "WD Alvo" (com /targetexact da lista) e a coloca no cursor para arrastar pra barra. A macro se atualiza sozinha quando a lista muda (fora de combate).

## 1.6.20

### Corrigido
- Tecla de alvo da Black list: o botao agora reage so ao apertar (antes reagia ao apertar e ao soltar, o que podia disparar duas vezes por aperto).

## 1.6.19

### Corrigido
- Tecla de alvo da Black list nao funcionava com algo ja targetado (o comando de combate usava [noexists]). Agora sobrepoe o alvo atual.

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
