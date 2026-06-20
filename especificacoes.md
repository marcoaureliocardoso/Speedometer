# Especificação Técnica de Projeto (Software Specification Document)

Este documento é a fonte de verdade para a implementação do aplicativo de monitoramento de velocidade e auxílio por voz. Requisitos que dependem de dados externos devem expor o respectivo grau de confiança; a sinalização física e a regulamentação oficial sempre prevalecem sobre as informações exibidas.

---

## 1. Visão Geral do Sistema

### 1.1 Objetivo do Produto

O aplicativo monitora a velocidade do automóvel em tempo real via GPS, fornece alertas de voz ao cruzar faixas de 5 km/h e identifica, quando houver dados confiáveis, o limite de velocidade mapeado para a via trafegada.

### 1.2 Público-Alvo e Contexto de Uso

Condutores de veículos automotores em rodovias ou vias urbanas. O dispositivo operará fixado em um suporte veicular, exigindo interface de alta legibilidade e mínima necessidade de interação física durante a condução.

---

## 2. Requisitos Funcionais (RF)

### RF-001: Captura de Velocidade via GPS

* **Descrição:** O sistema deve ler continuamente a localização do dispositivo para extrair a velocidade instantânea.
* **Amostragem:** O aplicativo deve solicitar atualizações a cada 1 segundo. A ausência de atualização pelo sistema operacional deve ser registrada como telemetria desatualizada.
* **Validação:** Leituras sem velocidade, com timestamp superior a 3 segundos em relação ao relógio do dispositivo ou com acurácia horizontal superior a 20 m devem ser descartadas. Velocidades negativas devem ser tratadas como 0 km/h.
* **Confiabilidade para alertas:** Quando a plataforma informar `speedAccuracy`, leituras com valor superior a 1,5 m/s não podem disparar ou confirmar alertas TTS. Quando `speedAccuracy` não for informado, a confirmação de TTS deve obedecer à regra alternativa de RF-002.
* **Localização desatualizada:** Após 3 segundos sem leitura válida, o sistema deve adicionar `locationStale` às razões de degradação, congelar o último valor numérico de velocidade com indicador visual e bloquear novos alertas de voz e consultas de via. Uma nova leitura válida remove essa razão. Após 10 segundos sem leitura válida, o limite deve assumir estado indisponível, mantendo o rastreamento ativo.
* **Conversão:** O dado nativo do sensor em m/s deve ser convertido para km/h pela fórmula:

$$\text{Velocidade}(km/h) = \text{Velocidade}(m/s) \times 3.6$$

* **Estabilização:** O valor numérico principal deve exibir a velocidade bruta válida. Somente o ponteiro radial deve receber filtro exponencial com $\alpha = 0,35$: $S_t = 0,35 \times V_t + 0,65 \times S_{t-1}$. A primeira leitura válida inicializa $S_t$ com $V_t$. Após 5 segundos sem leitura válida, o filtro deve ser reinicializado na próxima leitura válida. As regras de negócio de TTS usam leituras brutas válidas, conforme RF-002.

### RF-002: Lógica de Notificação por Voz (Gatilho Múltiplo de 5)

* **Descrição:** O aplicativo deve anunciar a faixa correspondente a um múltiplo positivo de 5 km/h sempre que ela for cruzada, tanto na aceleração quanto na desaceleração.
* **Regra de transição:** Sejam $P = floor(velocidadeBrutaAnterior)$ e $C = floor(velocidadeBrutaAtual)$, calculados somente a partir de leituras brutas válidas.
  * Se $C > P$, as faixas cruzadas são os múltiplos positivos de 5 no intervalo $(P, C]$.
  * Se $C < P$, as faixas cruzadas são os múltiplos positivos de 5 no intervalo $[C, P)$.
  * Se $C = P$, não há alerta.
  * Se houver uma única faixa cruzada, ela deve ser anunciada.
  * Se houver mais de uma faixa cruzada em uma leitura, somente a faixa mais próxima de $C$ deve ser anunciada, para impedir uma fila de áudio obsoleta.
  * A faixa 0 km/h nunca deve ser anunciada.
  * **Confirmação de cruzamento:** Ao detectar uma faixa cruzada, o sistema deve registrá-la como pendente. O alerta só deve ser emitido se a próxima leitura bruta válida permanecer no mesmo lado da faixa: maior ou igual à faixa em aceleração, ou menor ou igual à faixa em desaceleração. Se retornar ao lado oposto, o cruzamento pendente deve ser descartado.
  * **Sem `speedAccuracy`:** Quando a plataforma não informar `speedAccuracy`, a confirmação de cruzamento exige duas leituras brutas válidas consecutivas com acurácia horizontal de no máximo 10 m e intervalo entre 0,8 e 2 segundos.
  * **Histerese:** Para cada faixa e sentido, após um anúncio, o mesmo anúncio só poderá ser rearmado quando a velocidade bruta permanecer por duas leituras válidas a pelo menos 2 km/h do lado oposto da faixa. Para anúncio ascendente da faixa 15, por exemplo, o rearme exige duas leituras de no máximo 13 km/h; para anúncio descendente, duas leituras de no mínimo 17 km/h.
* **Exemplos de comportamento:**
  * $14\ km/h \rightarrow 15\ km/h$: fala "15 quilômetros por hora".
  * $16\ km/h \rightarrow 15\ km/h$: fala "15 quilômetros por hora".
  * $15\ km/h \rightarrow 15\ km/h$: sem áudio.
  * $14\ km/h \rightarrow 16\ km/h$: fala "15 quilômetros por hora".
  * $14\ km/h \rightarrow 26\ km/h$: fala "25 quilômetros por hora".
  * $26\ km/h \rightarrow 14\ km/h$: fala "15 quilômetros por hora".
* **Arbitragem de áudio:** O `AudioAnnouncementCoordinator` deve manter no máximo uma fala ativa e não deve manter fila de alertas de faixa. Alertas de mudança de limite têm prioridade sobre alertas de faixa. Um novo alerta de limite deve cancelar e substituir alerta de limite anterior ainda ativo e descartar alertas de faixa pendentes. Alertas de faixa nunca devem interromper alerta de limite.

### RF-003: Detecção de Velocidade Máxima da Via ($V_{max}$)

* **Descrição:** O sistema deve identificar o limite de velocidade mapeado para a via atual por meio de consulta espacial às vias do OpenStreetMap (OSM), usando posição e rumo do veículo.
* **Provedor de dados:** API Overpass do OpenStreetMap (OSM), filtrando pelas tags `highway` e `maxspeed`.
* **Acurácia para limite de via:** A velocidade pode continuar sendo exibida para leituras com acurácia horizontal de até 20 m, mas uma nova busca ou troca de via só pode ocorrer quando a acurácia horizontal for de no máximo 15 m, a acurácia de rumo for de no máximo 20 graus e, quando informada pela plataforma, a acurácia de velocidade for de no máximo 1,5 m/s. Quando a plataforma não fornecer acurácia de rumo, o app deve calculá-lo a partir de duas posições válidas separadas por pelo menos 10 m. Sem essas condições, o app deve emitir `gpsWeak` e manter somente a via anteriormente confirmada quando ela ainda estiver a até 15 m da posição; caso contrário, o limite deve ser desconhecido.
* **Seleção da via:** Acima de 10 km/h e com acurácia compatível, cada segmento candidato a até 15 m deve receber a pontuação $score = D + R + C + S$, onde $D = 40 \times max(0, 1 - distanciaMetros/15)$, $R = 30 \times max(0, 1 - diferencaAngularGraus/45)$, $C = 20$ quando o candidato for a via anteriormente confirmada e $0$ nos demais casos, e $S = 10$ quando o sentido único for compatível. Candidatos incompatíveis com o sentido único devem ser rejeitados. Apenas o candidato com pontuação maior ou igual a 70 pode ser selecionado. Abaixo de 10 km/h, ou sem rumo confiável, o aplicativo deve manter apenas a via já confirmada se a posição ainda estiver a até 15 m da sua geometria; caso contrário, o limite deve ser considerado desconhecido.
* **Confirmação:** Uma via candidata é confirmada somente após atender à regra de seleção em duas leituras válidas consecutivas, separadas por no mínimo 1 segundo. A troca de via é confirmada quando uma candidata com `way.id` diferente satisfaz essa mesma regra. Pontuação inferior a 70 deve produzir o estado de baixa confiança e nunca disparar alerta de limite.
* **Ambiguidade vertical:** Quando candidatos próximos tiverem `bridge`, `tunnel`, `layer` diferente ou interseção geométrica, a troca de via não pode ocorrer imediatamente. A nova candidata deve permanecer compatível por 50 m percorridos ou três leituras válidas consecutivas. Sem confirmação, o app deve manter a via anterior; se ela não for mais compatível, deve emitir `roadMatchLowConfidence` e usar limite indisponível.
* **Tags direcionais:** Quando aplicáveis, `maxspeed:forward` e `maxspeed:backward` prevalecem sobre `maxspeed`, conforme o sentido de deslocamento e a orientação da via.
* **Cache e otimização:** Uma nova busca deve ocorrer quando o veículo sair da geometria da via selecionada, percorrer mais de 50 m desde a última busca bem-sucedida ou completar 60 segundos sem confirmação. Deve haver intervalo mínimo de 10 segundos entre consultas e retentativa exponencial após falhas.
* **Ordem de consulta:** Com conectividade disponível, a consulta ao Overpass é a fonte preferencial. Sem conectividade, ou após timeout/falha do Overpass, o aplicativo deve consultar a base offline definida em RF-006 antes de declarar o limite desconhecido.
* **Expiração:** Caso não haja limite confirmado, online ou offline, por 250 m percorridos ou 2 minutos, o estado do limite deve passar para desconhecido. O aplicativo não deve inferir um limite legal padrão.
* **Cálculos geoespaciais:** Coordenadas devem usar WGS-84. A distância até uma via deve ser calculada como distância ponto-segmento em projeção local; o rumo deve ser expresso em graus verdadeiros de 0 a 360; e a diferença angular deve ser $min(abs(a-b), 360-abs(a-b))$.

### RF-004: Dashboard Dinâmico (Medidor Graduado)

* **Descrição:** Exibir velocímetro analógico/radial cuja escala se adapta em tempo real ao limite confiável da via.
* **Cálculo dos limites da escala:**
  * **Limite inferior ($V_{min}$):** $\frac{V_{max}}{2}$.
  * **Limite superior ($V_{max}$):** $V_{max}$.
* **Comportamento do ponteiro:**
  * Se a velocidade atual for menor ou igual a $V_{min}$, o ponteiro deve apontar fixamente para o início da escala.
  * Se a velocidade atual for maior que $V_{max}$, o ponteiro deve permanecer no fim da escala, em vermelho pulsante.
  * O ponteiro nunca deve ultrapassar os limites visuais do medidor.
  * O valor numérico real da velocidade deve permanecer visível em todos os estados.
  * Quando $V_{max}$ for desconhecido, o painel deve exibir a velocidade atual sem escala legal e com o rótulo "Limite indisponível".

### RF-005: Alertas de Voz por Mudança de Via

* **Descrição:** Após a confirmação de uma via e de um limite válido, o aplicativo deve emitir: *"Atenção: Novo limite de velocidade: X quilômetros por hora"*.
* **Primeira leitura:** A primeira detecção válida após o início do rastreamento também deve ser anunciada.
* **Supressão de duplicidade:** O mesmo limite não deve ser anunciado novamente durante 30 segundos, exceto quando uma mudança de via tiver sido confirmada.
* **Fonte offline:** Quando o limite confirmado vier de dados offline frescos, o alerta deve informar a origem: *"Atenção: Limite offline registrado: X quilômetros por hora"*. Limites offline desatualizados nunca devem gerar novo alerta de voz.

### RF-006: Base Offline de Limites

* **Objetivo:** O aplicativo deve permitir que o usuário construa e mantenha regiões locais de limites de velocidade para uso sem conexão de dados, sem CDN, servidor ou pacote pré-gerado de propriedade do projeto.
* **Seleção da região:** O usuário deve escolher uma região circular de até 25 km de raio ou uma área de até 500 km². A interface deve permitir usar a localização atual, informar coordenadas manualmente ou abrir aplicativo de mapas externo para escolher e compartilhar o ponto central, sempre com controle de raio no aplicativo. O contrato `MapSelectionProvider.selectPoint()` deve retornar `MapPoint(latitude, longitude, source)`; latitude deve estar entre -90 e 90, longitude entre -180 e 180 e ambos devem ser valores finitos. Se o aplicativo externo não responder, for cancelado ou retornar valor inválido, a interface deve voltar às opções de localização atual e coordenadas manuais. Busca por cidade/endereço pode usar o geocodificador nativo somente após aviso de rede; se ele não estiver disponível, as demais formas de seleção devem continuar possíveis. Regiões maiores devem ser recusadas com mensagem que explique o limite.
* **Prévia e sobreposição:** Antes de confirmar a construção, a interface deve exibir área, quantidade estimada de células, intervalo estimado de espaço e tempo de construção. Áreas sobrepostas a regiões existentes devem ser mescladas e não podem gerar células duplicadas.
* **Construção local:** A região deve ser dividida em células de no máximo 5 km × 5 km. Para cada célula, o app deve consultar diretamente a API Overpass, obter vias elegíveis e construir a base local no próprio dispositivo.
* **Fontes offline:** A construção por Overpass público é destinada a piloto e uso limitado, obedecendo às cotas deste documento. Para regiões grandes ou uso intensivo, o usuário deve poder importar manualmente um extrato regional OSM no formato `.osm.pbf`, selecionado pelo sistema de arquivos. A importação deve processar apenas vias elegíveis e construir a mesma base SQLite/R-tree, sem enviar dados ao projeto. Não pode haver fallback silencioso para outro endpoint público.
* **Limites e processamento PBF:** O arquivo `.osm.pbf` deve ter no máximo 1 GB e ser processado por streaming, sem carregamento integral em memória. O importador deve limitar a memória adicional a 64 MB, blocos descomprimidos a 32 MB e transações SQLite a no máximo 1.000 vias. A importação deve ser cancelada se ultrapassar 30 minutos, o limite de memória ou a quota de disco.
* **Staging transacional:** A importação deve ser feita em banco de staging cifrado. Somente após leitura completa, validação e cálculo de SHA-256, os dados podem substituir ou mesclar a região na base principal. Em falha, o staging deve ser removido e os dados ativos devem permanecer inalterados.
* **Metadados de importação:** O extrato importado deve registrar `sourceDate`, `bounds`, `originLabel`, SHA-256 e versão do formato. Quando `sourceDate` ou `bounds` estiver ausente, os dados devem ser importados como desatualizados e não podem disparar TTS até atualização por fonte com data verificável. Se os limites não intersectarem o Brasil, a importação deve ser rejeitada.
* **Conflito de fontes:** Cada registro deve armazenar `sourceKind` (`overpass` ou `pbf_import`) e `sourceDate`. Para a mesma via, dado online confirmado prevalece durante rastreamento online; sem rede, a seleção local deve preferir o dado com `sourceDate` mais recente. Uma fonte não pode sobrescrever fisicamente a outra.
* **Atualização de importação:** A interface deve exibir origem, data e SHA-256 de cada região importada. Ao importar região sobreposta, o usuário deve escolher entre `substituir` e `manter separado`; o padrão é substituir em transação. A validade de dados importados segue os períodos de 30 e 90 dias definidos neste requisito.
* **Cancelamento de importação:** A importação deve validar permissão de leitura antes do início. Ela pode ser cancelada, mas não precisa ser retomável; após cancelamento, o usuário deve reiniciá-la. O cancelamento nunca pode alterar os dados ativos.
* **Vias elegíveis:** Devem ser aceitas somente vias `motorway`, `trunk`, `primary`, `secondary`, `tertiary`, `unclassified`, `residential`, `living_street` ou `service`. Vias com `motor_vehicle=no`, `motorcar=no`, `access=no` ou `access=private` devem ser descartadas. Para `oneway=-1`, a geometria deve ser invertida antes de determinar a tag direcional aplicável.
* **Conteúdo local:** Para cada via, a base deve armazenar `way.id` do OSM, geometria com ao menos dois pontos, nome opcional, `maxspeed`, `maxspeed:forward`, `maxspeed:backward`, data de coleta e identificador da célula e da região.
* **Armazenamento:** As regiões devem ser persistidas localmente em banco geoespacial SQLite com índice R-tree, permitindo busca de segmentos em um raio de 30 m sem acesso à rede. O modelo deve conter as tabelas `offline_regions`, `offline_cells`, `ways` e `cell_ways`; a última registra a associação entre células e vias, impedindo que uma via ainda usada por outra célula seja removida.
* **Seleção local:** A seleção de uma via offline deve obedecer exatamente aos critérios de distância, rumo e confirmação definidos em RF-003.
* **Fila e retomada:** A construção deve processar no máximo uma célula por vez, persistindo para cada célula seu estado (`pending`, `downloading`, `complete`, `complete_empty`, `split`, `failed` ou `stale`), data da tentativa e número de falhas. `complete_empty` representa consulta válida sem via elegível e deve resultar em "Limite indisponível" naquela área. O usuário deve poder pausar, retomar ou cancelar a construção sem perder células concluídas.
* **Ciclo de vida das células:** `complete` e `complete_empty` são frescos por 30 dias, desatualizados até 90 dias e expiram após esse prazo. `split` só pode ser considerado concluído quando todas as subcélulas concluírem. Para `failed`, devem ocorrer retentativas automáticas após 15 minutos, 1 hora e 6 horas; após a terceira falha, a célula só pode ser retomada por ação manual do usuário.
* **Continuidade de regiões:** Ao atingir o máximo de 30 células de uma sessão, a região deve assumir o estado `paused_quota`. O usuário pode ativar a preferência "continuar automaticamente"; nesse caso, o app pode agendar no máximo duas sessões por dia, em Wi-Fi e com o dispositivo carregando. Sem essa preferência, a retomada deve ser manual. A interface deve exibir células restantes e estimativa de conclusão.
* **Prioridade operacional:** A construção e atualização regional só podem executar enquanto o rastreamento estiver parado. Ao iniciar o rastreamento, qualquer construção em andamento deve ser pausada antes da próxima consulta; consultas de condução têm prioridade absoluta.
* **Uso de rede e limite de carga:** A construção e a atualização automática devem ocorrer somente em rede Wi-Fi, salvo autorização explícita do usuário para dados móveis. Deve haver intervalo mínimo de 5 segundos entre células, máximo de 30 células por sessão e somente uma consulta Overpass em andamento. Timeout, resposta `429` ou resposta `5xx` devem pausar a construção por 30 minutos; consultas de construção também devem respeitar o circuit breaker de RNF-009.
* **Consentimento de construção:** A construção regional requer consentimento explícito próprio para enviar a área selecionada ao Overpass. Esse consentimento pode ser dado mesmo quando o modo de rastreamento estiver em `somente offline`, pois se aplica exclusivamente à construção solicitada pelo usuário.
* **Revogação de construção:** O `ConstructionConsentController` deve permitir revogar o consentimento de construção. Ao revogar, deve cancelar a tarefa em curso, remover retomadas automáticas e bloquear novas consultas de construção. O usuário deve escolher entre manter os dados já baixados ou apagar regiões e dados locais associados; essa decisão não pode alterar o modo de dados do rastreamento.
* **Subdivisão adaptativa:** Se uma consulta exceder 20 segundos, 5 MB de resposta ou 20.000 elementos, a célula deve mudar para `split` e ser subdividida em quatro subcélulas. A subdivisão pode continuar até células de 1,25 km × 1,25 km; abaixo desse tamanho, a célula deve ser marcada como `failed` e ficar disponível para nova tentativa manual.
* **Validação e atualização transacional:** Antes de gravar uma célula, o app deve validar o esquema do retorno, a presença de geometria com ao menos dois pontos e a regra de parse de limites. A substituição dos dados de uma célula deve ocorrer em transação, mantendo os dados anteriores até o sucesso da gravação.
* **Atualização incremental:** A atualização deve consultar somente células desatualizadas, incompletas ou com falha; nunca deve reconstruir toda a região quando houver células ainda válidas. A tabela `ways` deve manter a versão mais recente de cada `way.id`, enquanto a validade de cobertura permanece vinculada à célula.
* **Validade:** Os dados de cada célula são **frescos** até 30 dias desde sua coleta e podem alimentar interface e alertas de voz. Entre 31 e 90 dias, são **desatualizados** e podem alimentar apenas a interface, sem alertas de voz. Após 90 dias, os limites da célula devem ser considerados desconhecidos até nova coleta.
* **Transparência:** Quando o limite vier da base offline, a interface deve exibir "Limite offline" e a data de coleta da célula. Para célula desatualizada, deve exibir também "Dados offline desatualizados". A sinalização oficial da via continua prevalecendo.
* **Ausência de cobertura:** Se não houver célula válida que contenha a posição atual, a interface deve exibir "Limite indisponível"; nunca deve estimar um valor legal.

### RF-007: Controles Operacionais e Preferências

* **Rastreamento:** A tela principal deve disponibilizar controle grande e inequívoco para iniciar e encerrar o rastreamento. O serviço em segundo plano deve ser encerrado quando o usuário encerrar o rastreamento.
* **Modos de voz:** O usuário deve poder escolher entre `silencioso`, `limites apenas` e `limites e faixas de 5 km/h`. A preferência deve ser persistida localmente e aplicada antes do próximo evento de voz.
* **Configurações de voz:** O usuário deve poder ajustar o volume relativo e a velocidade de fala do TTS.
* **Modo de dados:** O `DataModeController` deve solicitar antes do primeiro rastreamento a escolha entre `online e offline`, `somente offline` ou `cancelar`. A opção online deve informar que a posição atual será enviada diretamente à API pública do OSM/Overpass para identificar a via. Sem aceite explícito, o modo online não pode ser ativado. Ao mudar para `somente offline`, o controlador deve cancelar consulta de rastreamento em curso, ignorar resposta tardia, bloquear novas consultas de posição e adicionar `onlineDataDisabled` às razões de degradação. A escolha deve poder ser alterada nas configurações.
* **Correção de dados:** Para limite ausente ou aparentemente incorreto, o usuário deve poder abrir a via atual no OpenStreetMap para correção manual e escolher "Ignorar limite desta via nesta sessão". A segunda ação deve suprimir somente alertas associados à `way.id` atual até o rastreamento terminar; ela não pode permitir edição manual de `Vmax`. Essas ações só podem estar disponíveis quando o rastreamento estiver encerrado.
* **Regiões offline:** O usuário deve poder acessar o gerenciamento de regiões definido em RF-006 fora da tela de condução. Durante o rastreamento ativo, a tela de condução não deve expor busca, seleção de região, abertura de OSM ou controles de configuração detalhada.

---

## 3. Requisitos Não-Funcionais (RNF)

* **RNF-001 (Plataforma e background):** A primeira versão suportará Android 10 (API 29) ou superior. O rastreamento de GPS e os gatilhos de voz devem funcionar com a tela apagada ou outro app em primeiro plano, mediante permissões de localização precisa e em segundo plano, serviço em primeiro plano e notificação persistente. O rastreamento em segundo plano só pode ser iniciado pelo usuário enquanto a interface estiver visível.
* **RNF-002 (Latência de áudio):** Após a leitura bruta válida que confirma um cruzamento pendente, o evento de domínio deve ser gerado em até 150 ms e o comando de fala deve ser enviado ao motor TTS em até 300 ms após esse evento. O TTS deve ser inicializado antes do rastreamento. O tempo até o áudio audível não é requisito, pois depende do dispositivo e do sistema operacional.
* **RNF-003 (Robustez de conexão):** Na ausência de internet, o velocímetro local deve continuar funcionando e a base offline de RF-006 deve ser consultada. O último limite confirmado poderá ser exibido somente até expirar conforme RF-003; depois disso, a interface deve apresentar "Limite indisponível".
* **RNF-004 (Privacidade):** Dados de localização não devem ser enviados a servidores próprios nem persistidos além do cache temporário necessário ao funcionamento do aplicativo.
* **RNF-005 (Transparência):** A interface deve informar que os limites provêm do OSM e que a sinalização oficial da via prevalece.
* **RNF-006 (Áudio):** Os alertas TTS devem usar `pt-BR` e a categoria de áudio de assistência à navegação. Na inicialização, o aplicativo deve verificar a disponibilidade de voz `pt-BR`. Se não estiver disponível, deve adicionar `ttsUnavailable` às razões de degradação, desabilitar falas e manter avisos visuais; fora do rastreamento, deve oferecer atalho para as configurações TTS do Android. O aplicativo não deve solicitar foco de áudio exclusivo, interromper áudio de outros aplicativos ou usar outro idioma como fallback.
* **RNF-007 (Acessibilidade visual):** A velocidade numérica deve ter tamanho mínimo de 96 sp em orientação retrato. Textos e indicadores essenciais devem possuir contraste mínimo de 4,5:1 contra o fundo; a cor vermelha de excesso nunca pode ser o único indicador do estado.
* **RNF-008 (Armazenamento offline):** Antes da construção, o aplicativo deve informar a área selecionada e uma estimativa de espaço necessário. Deve também informar o espaço total ocupado, a cobertura concluída, a data da última coleta e a quantidade de células pendentes ou com falha. A remoção de uma região deve liberar todos os seus dados locais.
* **RNF-009 (Resiliência do Overpass):** Deve haver no máximo uma requisição Overpass em andamento, considerando tanto o rastreamento online quanto a construção de regiões offline. Após três falhas consecutivas, o cliente deve abrir um circuit breaker por 5 minutos, sem realizar novas requisições ao Overpass nesse intervalo. Após três aberturas do circuit breaker em uma janela de 24 horas, a construção regional deve ser suspensa até nova ação manual do usuário. Durante o circuito aberto, o aplicativo deve usar a base offline ou o estado de limite indisponível. A implementação deve depender da abstração `RoadDataProvider`, com Overpass como provedor inicial, e não pode alternar silenciosamente para outro endpoint.
* **RNF-010 (Diagnóstico sem localização):** O aplicativo deve manter apenas contadores locais agregados de falhas de GPS, Overpass, cobertura offline e baixa confiança de via. Nenhuma coordenada, rumo ou identificador de via deve ser incluído nesses diagnósticos. O usuário pode escolher "Exportar/compartilhar relatório de diagnóstico"; a ação deve gerar JSON ou ZIP local com `schemaVersion`, mostrar prévia e usar o compartilhamento nativo, contendo somente versão do aplicativo, versão Android e contadores agregados. Não pode haver telemetria automática nem destino de suporte predefinido.
* **RNF-011 (Transparência de rede):** Antes da primeira construção de região, o aplicativo deve informar que a área selecionada será consultada diretamente na API pública do OSM/Overpass, sem intermediário do projeto. O consentimento de RF-007 deve cobrir também as consultas online durante o rastreamento.
* **RNF-012 (Construção em segundo plano):** A construção regional deve usar uma tarefa Android única, com Wi-Fi, bateria não baixa e armazenamento disponível como pré-condições. A tarefa deve exibir notificação de progresso com as únicas ações `pausar` e `cancelar` e deve ser pausada ao iniciar o rastreamento. O identificador e o estado da tarefa devem ser persistidos; após reinício do dispositivo, apenas construções que o usuário deixou ativas podem ser reagendadas. Enquanto a chave do Keystore não estiver disponível antes do primeiro desbloqueio, a tarefa deve permanecer em `waiting_for_unlock`, sem falhar ou recriar a base. A perda de Wi-Fi deve pausar a tarefa sem novas requisições e sua retomada deve respeitar as pré-condições. Fechar a notificação não pode apagar o progresso já gravado.
* **RNF-013 (Atribuição):** A tela de gerenciamento de regiões offline e a tela Sobre devem exibir "© OpenStreetMap contributors" e disponibilizar link para a página de atribuição do OpenStreetMap.
* **RNF-014 (Armazenamento e migração):** A base offline deve possuir `schemaVersion`. Migrações devem ser transacionais e idempotentes. Em falha de migração ou incompatibilidade de versão, o app deve preservar preferências, remover somente a base geoespacial e marcar as regiões para reconstrução.
* **RNF-015 (Quota de armazenamento):** A quota padrão da base offline é 500 MB, configurável pelo usuário até 1 GB. A quota efetiva deve ser $min(quotaEscolhida, 1\ GB, 10\%\ do\ espaço\ livre\ antes\ da\ construção)$. Antes de iniciar uma célula, o app deve validar que a estimativa da célula mais reserva de 20 MB cabe na quota efetiva disponível; se insuficiente, deve pausar a construção e solicitar ação do usuário, sem remover regiões automaticamente.
* **RNF-016 (Proteção local):** A base offline deve ser criptografada com chave protegida pelo Android Keystore. A base, filas de construção e diagnósticos locais devem ser excluídos do Android Auto Backup. Em falha de descriptografia ou chave invalidada, o app deve adicionar `offlineDataResetRequired`, fechar e remover banco, WAL, SHM e filas cifradas, preservar preferências não sensíveis e oferecer reconstrução de regiões somente após novo consentimento. O app deve oferecer a ação "Limpar todos os dados offline", mediante confirmação, removendo regiões, células, filas e métricas locais.
* **RNF-017 (Destinos de rede):** O `NetworkDestinationRegistry` deve listar cada destino externo e sua finalidade: Overpass para limites e construção regional, geocodificador para busca e `MapSelectionProvider` quando aplicável. Antes do primeiro uso de cada destino, o aplicativo deve mostrar aviso específico. No modo somente offline, recursos que dependam de rede, incluindo geocodificação e seleção de mapa externa online, devem permanecer desabilitados, exceto a construção regional após o consentimento próprio definido em RF-006.
* **RNF-018 (Escopo geográfico):** A primeira versão é restrita ao Brasil, com interface e TTS em `pt-BR` e unidade km/h. O aplicativo deve incluir `BoundaryDataset` offline da fronteira brasileira, composto por polígono simplificado, `version`, `sourceDate`, `checksum` e identificador de release. Deve aplicar teste ponto-em-polígono WGS-84 antes de consultar ou usar limite de via. Dentro de 500 m da fronteira, deve adicionar `countryBoundaryUncertain` às razões de degradação e exibir "Limite indisponível". Fora do Brasil, o aplicativo deve manter apenas o velocímetro local e exibir "Limite indisponível". Se o dataset estiver ausente ou inválido, consultas de limite devem ser bloqueadas. Atualizações do dataset só podem ser distribuídas em nova versão do aplicativo. Suporte a outro país exige nova especificação de idioma, regras de parse e fontes de dados.
* **RNF-019 (Áudio indisponível):** Se o sistema negar ou falhar a reprodução de áudio de assistência, o app deve descartar alertas de faixa, registrar diagnóstico local `audioUnavailable` e exibir indicador visual. Para alerta de limite, deve exibir destaque visual e não tentar reproduzi-lo posteriormente quando estiver obsoleto.
* **RNF-020 (Desempenho de importação PBF):** No dispositivo-alvo mínimo (Android 10 com 4 GB de RAM), a importação de arquivo de até 1 GB deve usar no máximo 64 MB de memória adicional, concluir em até 30 minutos, exibir progresso e não degradar o rastreamento, que mantém prioridade absoluta.

---

## 4. Arquitetura do Projeto (Flutter)

O projeto seguirá Clean Architecture, com dependências direcionadas da apresentação para o domínio e do domínio para contratos abstratos. Implementações de GPS, Overpass, cache e TTS devem permanecer na camada de dados ou em adaptadores de infraestrutura.

```
lib/
│
├── core/
│   ├── controllers/
│   │   ├── data_mode_controller.dart
│   │   └── construction_consent_controller.dart
│   ├── errors/
│   │   └── failures.dart
│   ├── constants/
│       ├── tracking_constants.dart
│       ├── road_limit_source.dart
│       ├── road_data_source_kind.dart
│       ├── road_limit_status.dart
│       ├── telemetry_degraded_reason.dart
│       └── offline_cell_status.dart
│   └── providers/
│       ├── road_data_provider.dart
│       └── map_selection_provider.dart
│
├── data/
│   ├── datasources/
│   │   ├── location_local_data_source.dart
│   │   ├── overpass_remote_data_source.dart
│   │   ├── road_cache_local_data_source.dart
│   │   ├── offline_road_limit_data_source.dart
│   │   ├── offline_region_builder_data_source.dart
│   │   ├── overpass_request_coordinator.dart
│   │   ├── offline_database_migrator.dart
│   │   ├── osm_pbf_import_data_source.dart
│   │   ├── pbf_import_staging_data_source.dart
│   │   └── tts_local_data_source.dart
│   ├── providers/
│   │   ├── overpass_road_data_provider.dart
│   │   └── external_map_selection_provider.dart
│   ├── models/
│   │   ├── road_info_model.dart
│   │   └── offline_region_model.dart
│   └── repositories/
│       ├── tracking_repository_impl.dart
│       ├── road_limit_repository_impl.dart
│       └── tts_repository_impl.dart
│
├── domain/
│   ├── entities/
│   │   ├── telemetry.dart
│   │   ├── road_info.dart
│   │   └── offline_region.dart
│   ├── repositories/
│   │   ├── tracking_repository.dart
│   │   ├── road_limit_repository.dart
│   │   └── tts_repository.dart
│   └── usecases/
│       ├── process_speed_tts_usecase.dart
│       ├── get_current_telemetry_stream_usecase.dart
│       ├── announce_road_limit_usecase.dart
│       └── manage_offline_regions_usecase.dart
│
└── presentation/
    ├── bloc/
    │   ├── telemetry_bloc.dart
    │   ├── telemetry_event.dart
    │   └── telemetry_state.dart
    └── pages/
        └── dashboard_page.dart
```

O polígono de fronteira deve estar no asset de projeto `assets/boundaries/brazil_simplified.geojson`, com metadados em `assets/boundaries/brazil_simplified.metadata.json`; ambos devem ser declarados no `pubspec.yaml`.

---

## 5. Mapeamento de Dados e APIs

### 5.1 Query de Integração com Overpass API (OpenStreetMap)

A busca por dados da via deve ser feita por `POST` para `https://overpass-api.de/api/interpreter`. O timeout de rede da aplicação deve ser de no máximo 5 segundos.

**Corpo da query:**

```overpass
[out:json][timeout:5];
(
  way(around:30, [LATITUDE], [LONGITUDE])[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)$"][maxspeed];
  way(around:30, [LATITUDE], [LONGITUDE])[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)$"]["maxspeed:forward"];
  way(around:30, [LATITUDE], [LONGITUDE])[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)$"]["maxspeed:backward"];
);
out tags geom;
```

**Mapeamento do payload de retorno:**

```json
{
  "elements": [
    {
      "type": "way",
      "id": 12345678,
      "tags": {
        "highway": "primary",
        "maxspeed": "110",
        "name": "Rodovia Governador Mário Covas"
      },
      "geometry": [
        { "lat": -23.0000, "lon": -46.0000 },
        { "lat": -23.0005, "lon": -46.0005 }
      ]
    }
  ]
}
```

* **Regra de parse:** Valores numéricos sem unidade são interpretados como km/h. Valores com sufixo `mph` devem ser convertidos para km/h e arredondados ao inteiro mais próximo. Valores ausentes, `signals`, `none`, `variable`, compostos ou não reconhecidos devem resultar em limite desconhecido. Valores simbólicos, como `BR:urban`, não devem ser convertidos automaticamente em limite legal. `maxspeed:advisory` nunca deve ser tratado como limite legal. A presença de `maxspeed:lanes`, `maxspeed:variable` ou `maxspeed:conditional` deve resultar em limite desconhecido, mesmo que exista `maxspeed` geral. Quando só houver limite específico de outro veículo, como `maxspeed:hgv`, sem `maxspeed` geral válido, o limite deve ser desconhecido. A mesma regra deve ser aplicada aos dados importados para a base offline.
* **Limites condicionais:** A primeira versão não deve interpretar condições de horário, obras, clima, sinalização variável ou limites específicos de faixa/veículo.

### 5.2 Query de Construção de Célula Offline

Para construir uma célula, o app deve consultar a API Overpass com os limites geográficos da célula, na ordem `sul, oeste, norte, leste`:

```overpass
[out:json][timeout:20];
(
  way([SUL], [OESTE], [NORTE], [LESTE])[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)$"][maxspeed];
  way([SUL], [OESTE], [NORTE], [LESTE])[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)$"]["maxspeed:forward"];
  way([SUL], [OESTE], [NORTE], [LESTE])[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)$"]["maxspeed:backward"];
);
out tags geom;
```

Uma célula só pode ser marcada como `complete` após a resposta ser validada e gravada com sucesso. Resposta válida sem via elegível deve marcá-la como `complete_empty`. Timeout, falha de rede ou resposta inválida devem marcar a célula como `failed`, preservando seus dados anteriormente válidos quando existirem.

---

## 6. Plano de Gerenciamento de Estado (BloC Pattern)

### 6.1 Estados do Sistema (`TelemetryState`)

* `TelemetryInitial`: estado antes do consentimento da permissão de GPS.
* `TelemetryPermissionDenied`: informa que a permissão de localização foi negada, incluindo a distinção entre negativa temporária e permanente.
* `TelemetryLocationServiceDisabled`: informa que o serviço de localização do dispositivo está desativado.
* `TelemetryLoading`: aguardando a primeira coordenada válida do sensor.
* `TelemetryTrackingActive`: contém a telemetria atualizada, independentemente da disponibilidade de limite.
  * Campos: `double currentSpeed`, `double filteredNeedleSpeed`, `double? maxSpeed`, `double? minGaugeSpeed`, `String? roadName`, `DateTime lastLocationAt`, `RoadLimitStatus limitStatus`, `RoadLimitSource? limitSource`, `DateTime? limitDataGeneratedAt`, `Set<TelemetryDegradedReason> degradationReasons`.
  * `limitStatus` deve ser `available` ou `unavailable`. Razões de degradação não formam estado BloC separado e devem ser apresentadas como indicadores discretos, sem ocultar a velocidade atual.
* `TelemetryError`: registra falha crítica de hardware ou permissões negadas.

`RoadLimitSource` deve ser uma enumeração com os valores `online` e `offline`.

`TelemetryDegradedReason` deve ser uma enumeração com os valores `gpsWeak`, `locationStale`, `offlineDataStale`, `offlineCoverageMissing`, `roadMatchLowConfidence`, `overpassUnavailable`, `onlineDataDisabled`, `audioUnavailable`, `ttsUnavailable`, `offlineDataResetRequired` e `countryBoundaryUncertain`.

`RoadLimitStatus` deve ser uma enumeração com os valores `available` e `unavailable`.

`RoadDataSourceKind` deve ser uma enumeração com os valores `overpass` e `pbfImport`.

`OfflineCellStatus` deve ser uma enumeração com os valores `pending`, `downloading`, `complete`, `complete_empty`, `split`, `failed` e `stale`.

---

## 7. Matriz de Análise de Riscos e Mitigações

| Sintoma / Falha | Causa Raiz | Ação de Mitigação Técnica |
| --- | --- | --- |
| Oscilação abrupta de velocidade parado | Ruído ou baixa precisão do sinal de GPS. | Descartar leituras inválidas conforme RF-001 e aplicar filtro exponencial antes da exibição e dos alertas. |
| Omissão ou atraso de alertas de voz | Latência ou enfileiramento de frases no TTS nativo. | Aplicar consolidação de RF-002, inicializar o TTS antecipadamente e cancelar apenas falas de faixa em execução. |
| Limite de via incorreto | Vias paralelas, cruzamentos ou dados OSM incompletos. | Selecionar por distância geométrica e rumo, expirar limites não confirmados e usar o estado de limite indisponível em baixa confiança. |
| Consumo elevado de bateria | GPS contínuo e serviço em primeiro plano. | Usar intervalo e critérios de cache definidos, interromper o serviço quando o usuário encerrar o rastreamento e monitorar consumo em dispositivo-alvo. |
| Indisponibilidade do Overpass | Falha de rede, timeout ou limitação do provedor. | Aplicar timeout, backoff exponencial, cache temporário e degradação para limite indisponível. |
| Região sem conexão de dados | Ausência de internet ou falha persistente do Overpass. | Consultar dados locais válidos da região; exibir a origem e a data da coleta; degradar para limite indisponível fora da cobertura ou após a validade. |
| Correspondência ambígua de via | Viadutos, retornos, cruzamentos ou baixa qualidade de GPS. | Pontuar candidatos por distância, rumo, continuidade e sentido único; não confirmar nem anunciar limite abaixo do limiar de confiança. |
| Fadiga por alertas | Excesso de falas durante a condução. | Permitir modos de voz persistentes, controle de volume e histerese de faixas. |
| Construção regional interrompida | Perda de conexão, fechamento do aplicativo ou falha em uma célula. | Persistir o estado por célula, permitir pausa e retomada e preservar células já concluídas. |
| Sobrecarga de consulta regional | Células densas ou sequência excessiva de requisições. | Limitar sessões e intervalo de consultas, pausar após erros de servidor e subdividir células grandes de forma adaptativa. |
| Exclusão indevida de dados locais | Uma via compartilhada é removida ao atualizar ou excluir uma célula. | Usar a associação `cell_ways` e remover a via apenas quando não houver mais referências. |

---

## 8. Critérios de Aceite para Validação do Código

1. **TTS:** Testes unitários devem cobrir os vetores `[13.8, 14.2, 14.9, 15.0, 15.2]`, `[14.0, 16.0, 16.1]`, `[14.0, 26.0, 26.1]`, `[26.0, 14.0, 13.9]` e `[15.1, 15.9]`. O vetor que cruza 15 km/h deve manter o alerta pendente em `15.0` e emitir uma única fala de 15 km/h após a confirmação em `15.2`. Leituras com `speedAccuracy` maior que 1,5 m/s não podem confirmar fala.
2. **Estabilidade do TTS:** Testes unitários devem verificar a histerese e a confirmação com oscilações nos arredores de 15 km/h, garantindo que `14,9 → 15,1 → 14,9 → 15,1` não gere fala e que `14,9 → 15,1 → 15,2` gere somente uma fala. Sem `speedAccuracy`, a confirmação deve exigir acurácia horizontal de até 10 m e intervalo de 0,8 a 2 segundos.
3. **Limites de via:** Testes unitários devem cobrir `maxspeed`, `maxspeed:forward` e `maxspeed:backward`, valores numéricos, em `mph`, ausentes, especiais, condicionais, por faixa, variáveis, consultivos e específicos de veículo. Testes de integração devem cobrir acurácia GPS acima e abaixo de 15 m, fórmulas de pontuação, distância ponto-segmento WGS-84, rumo indisponível, baixa velocidade, troca de via confirmada, perda de conexão e expiração de cache.
4. **Confiança de via:** Testes de integração devem validar a pontuação em vias paralelas, cruzamentos, retornos, sentido único incompatível, `bridge`, `tunnel`, `layer` divergente, troca bloqueada por ambiguidade vertical e pontuação abaixo de 70, garantindo que esses casos não gerem alerta de limite.
5. **Base offline:** Testes de integração devem validar os limites de área da região, seleção por localização atual, coordenadas manuais e aplicativo de mapas externo, retorno inválido/cancelado do `MapSelectionProvider`, geocodificador indisponível, prévia de área/células/espaço/tempo, mesclagem de sobreposições, divisão em células, construção com uma consulta por vez, importação manual `.osm.pbf` de até 1 GB por streaming, metadados de origem ausentes como dado desatualizado, rejeição de bounds fora do Brasil, SHA-256, staging transacional, cancelamento sem alteração dos dados ativos, conflito entre `overpass` e `pbfImport`, escolha de substituir/manter separado, pausa automática quando o rastreamento iniciar, retomada, cancelamento, persistência de células concluídas, busca local por segmento, filtros de via elegível, `oneway=-1`, limites direcionais, cobertura ausente, célula `complete_empty`, célula fresca, célula desatualizada, célula expirada, ausência de TTS com dado desatualizado, exibição da fonte e da data, bloqueio de dados móveis sem consentimento, falha e nova tentativa por célula após 15 min/1 h/6 h, conclusão de `split` somente após subcélulas, estado `paused_quota`, continuidade automática de no máximo duas sessões diárias, revogação do consentimento com manutenção ou remoção dos dados locais, atualização incremental, gravação transacional e remoção completa dos dados regionais.
6. **Controles operacionais:** Testes devem validar início e encerramento do rastreamento, persistência e aplicação dos três modos de voz, volume, velocidade de fala, abertura da via no OSM apenas com rastreamento encerrado, supressão da `way.id` somente durante a sessão e ausência de busca, seleção de região, abertura de OSM e controles detalhados durante a condução ativa.
7. **Resiliência:** Testes devem validar o limite de uma requisição Overpass simultânea, intervalo mínimo de 5 segundos entre células, máximo de 30 células por sessão, pausa de 30 minutos após timeout/`429`/`5xx`, abertura do circuit breaker após três falhas, duração de 5 minutos, subdivisão de célula densa até 1,25 km × 1,25 km e fallback para a base offline ou estado indisponível.
8. **Ciclo de vida:** Testes em dispositivo Android devem validar permissão negada temporária e permanentemente, localização desativada, tela apagada, outro app em primeiro plano, reinicialização do serviço de rastreamento, reinício do dispositivo durante construção, estado `waiting_for_unlock`, perda ou invalidação da chave do Keystore, perda de Wi-Fi e preservação de progresso após fechamento da notificação.
9. **Desempenho:** Em dispositivo-alvo definido pelo projeto, testes instrumentados devem comprovar que o evento de domínio é emitido em até 150 ms após a leitura de confirmação e que o comando TTS é emitido em até 300 ms após o evento. No dispositivo mínimo de RNF-020, testes devem comprovar importação PBF de até 1 GB em até 30 minutos, memória adicional de até 64 MB, progresso visível e prioridade do rastreamento.
10. **Interface:** O medidor deve redesenhar sem quebra de layout quando o limite superior, `limitStatus` ou `degradationReasons` de `TelemetryTrackingActive` mudar. O número principal deve refletir a velocidade bruta válida e o ponteiro deve refletir a velocidade filtrada. A velocidade deve respeitar o tamanho mínimo e os indicadores devem respeitar os critérios de contraste de RNF-007.
11. **Transparência:** A interface deve exibir a origem OSM, o aviso de prevalência da sinalização oficial e, quando aplicável, a origem offline e a data da coleta local.
12. **Atribuição e escopo:** A tela de regiões offline e a tela Sobre devem exibir a atribuição ao OpenStreetMap e seu link correspondente. Testes devem validar o polígono da fronteira brasileira, os metadados de versão/data/checksum, dataset ausente ou inválido, a faixa de incerteza de 500 m e a ausência de consultas/limites fora do Brasil.
13. **Consentimento:** Testes devem validar que o modo online não envia consultas de rastreamento antes do aceite explícito, que a mudança para somente offline cancela consulta ativa, ignora resposta tardia e bloqueia novas consultas de rastreamento, e que a construção regional no modo somente offline exige consentimento próprio. Devem validar também os avisos do `NetworkDestinationRegistry` para cada destino externo.
14. **Precisão e armazenamento:** Testes devem validar acurácia de rumo, acurácia de velocidade, cálculo de rumo por duas posições a 10 m e o comportamento `gpsWeak`. Devem também validar migração idempotente, recuperação de migração inválida, cálculo da quota efetiva, reserva de 20 MB por célula, exclusão do Auto Backup e limpeza completa dos dados offline.
15. **Arbitragem de áudio e telemetria desatualizada:** Testes devem validar que novo alerta de limite substitui alerta de limite anterior, descarta faixas pendentes e nunca é interrompido por faixa. Devem validar falha de áudio com descarte de faixa, indicador `audioUnavailable` e destaque visual de limite; voz `pt-BR` indisponível com `ttsUnavailable` e ausência de fallback de idioma. Devem validar também `locationStale` após 3 segundos, bloqueio de TTS/consulta de via, restauração por leitura válida e limite indisponível após 10 segundos.
16. **Reprodução de trajetos:** A suíte deve usar fixtures GPX anonimizadas e sintéticas por meio de `FakeLocationDataSource` com relógio controlado. Cada fixture deve declarar a via esperada, o limite, as razões de degradação e as falas TTS esperadas, cobrindo viadutos, túneis, vias paralelas, sinal GPS fraco, perda de rede e mudanças rápidas de faixa.
17. **Privacidade e diagnóstico:** Testes devem validar que o relatório de diagnóstico é gerado apenas após ação explícita, usa JSON ou ZIP com `schemaVersion`, mostra prévia e contém somente versão do aplicativo, versão Android e contadores agregados. O relatório não pode conter coordenadas, rumo, `way.id`, nome de via, texto de fala ou destino de suporte predefinido.
