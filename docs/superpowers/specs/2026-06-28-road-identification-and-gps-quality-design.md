# Identificação de via e qualidade do GPS

## Objetivo

Exibir a via atual sempre que ela puder ser identificada nos dados do
OpenStreetMap, mesmo quando a via não tiver `maxspeed`. A identificação da via,
a obtenção do limite de velocidade e os diagnósticos de qualidade devem ser
independentes.

## Problemas confirmados

1. A consulta Overpass atual só retorna vias com `maxspeed`,
   `maxspeed:forward` ou `maxspeed:backward`. Uma via sem essas etiquetas nunca
   pode ser exibida.
2. O primeiro pareamento de uma via bidirecional exige pontuação praticamente
   perfeita. Pequenas diferenças reais de posição ou rumo impedem a
   confirmação.
3. A direção da geometria completa da via é usada no pareamento. Isso rejeita
   deslocamentos no sentido inverso de vias bidirecionais e se comporta mal em
   vias curvas.
4. A incerteza da velocidade bloqueia a identificação da via, embora não
   determine a qualidade da posição.
5. O cliente depende de uma única instância Overpass e usa um timeout curto. A
   instância respondeu corretamente nos testes, mas também apresentou falhas
   intermitentes.
6. O aviso genérico "GPS com baixa precisão" mistura precisão de posição e
   precisão da velocidade.

## Decisão de arquitetura

Manter o Overpass como fonte única nesta etapa, ampliar a consulta para todas
as vias motorizáveis próximas e separar os resultados:

- `RoadMatch` identifica a via e contém `wayId`, nome ou referência, distância e
  limite opcional.
- O nome da via é obtido de `name`; quando ele não existir, `ref` é usado como
  identificação legível.
- A ausência ou rejeição de `maxspeed` não invalida o pareamento da via.
- A interface apresenta a via mesmo quando mostra "Limite indisponível".
- Alertas dependentes do limite só são processados quando o limite for válido.

Não será adicionado Nominatim nem um banco cartográfico offline nesta mudança.

## Consulta e resiliência do Overpass

A consulta deve buscar, num raio de 40 metros, todas as vias das classes
motorizáveis já aceitas pelo aplicativo, sem filtrar por `maxspeed`. O retorno
continua incluindo etiquetas e geometria.

O provedor usará uma lista ordenada de duas instâncias públicas documentadas:
`https://overpass-api.de/api/interpreter` como primária e
`https://maps.mail.ru/osm/tools/overpass/api/interpreter` como secundária. Cada
requisição deve enviar `Accept: application/json` e um `User-Agent` com nome e
versão do aplicativo. A segunda instância será tentada quando a primeira tiver
timeout, erro de transporte, HTTP 406, 408, 429 ou 5xx. Outros erros 4xx, que
indicam requisição ou consulta inválida, não devem ser mascarados por repetição.

Cada tentativa terá timeout de seis segundos. O provedor continuará impedindo
consultas concorrentes, mas manterá falhas e circuito aberto por endpoint, para
que uma instância indisponível não bloqueie a outra. Uma resposta válida, mesmo
sem vias, não conta como falha de conexão.

## Pareamento de via

### Geometria e direção

A distância e o rumo da via serão calculados sobre o segmento de geometria mais
próximo da posição, não entre o primeiro e o último ponto da via.

Para vias bidirecionais, a diferença angular será a menor diferença entre o
rumo do veículo e os dois sentidos do segmento. Para `oneway=yes` e
`oneway=-1`, apenas o sentido permitido será elegível.

### Qualidade da posição

A identificação depende da precisão horizontal, não da incerteza da
velocidade:

- posição com precisão horizontal acima de 20 metros não será pareada;
- entre 15 e 20 metros, a posição será marcada como degradada, mas ainda poderá
  manter uma via anteriormente confirmada;
- até 15 metros, novos pareamentos serão permitidos.

A incerteza da velocidade continuará controlando a validade da velocidade e dos
alertas, sem apagar ou impedir o nome da via.

### Confiança

Com rumo confiável, candidatos devem estar a no máximo 25 metros e ter diferença
angular de no máximo 90 graus. A pontuação será:

- até 60 pontos por proximidade, caindo linearmente de 60 a zero entre 0 e
  25 metros;
- até 30 pontos por alinhamento, caindo linearmente de 30 a zero entre 0 e
  90 graus;
- 10 pontos de continuidade para a via já confirmada.

Um novo candidato precisa alcançar 45 pontos e superar o segundo colocado por
ao menos 8 pontos. A via já confirmada pode ser mantida com 35 pontos, reduzindo
oscilações.

Sem rumo confiável, a via pode ser identificada apenas por distância quando o
candidato mais próximo estiver a até 15 metros e for pelo menos 10 metros mais
próximo que o segundo. Essa regra permite identificar a via parado ou em baixa
velocidade sem escolher arbitrariamente em cruzamentos.

Uma nova via continua exigindo confirmação por duas amostras separadas por pelo
menos um segundo. Uma via confirmada só é substituída por outro candidato que
satisfaça a mesma confirmação.

## Estado e interface

O controlador manterá separadamente:

- via confirmada;
- limite válido, que pode ser nulo;
- qualidade da posição;
- qualidade da velocidade;
- qualidade do rumo;
- disponibilidade da consulta online.

Os diagnósticos visíveis serão específicos:

- "Posição GPS com baixa precisão" para precisão horizontal degradada;
- "Velocidade GPS com baixa precisão" para incerteza da velocidade;
- "Direção insuficiente para confirmar a via" somente quando o rumo for
  necessário e o pareamento por distância também for ambíguo;
- "Consulta online indisponível" somente após todas as instâncias falharem;
- "Via não confirmada" quando houve resposta válida, mas nenhum candidato
  atingiu a confiança necessária.

Quando houver via sem limite, o cartão mostrará:

- `Via atual: <nome ou referência>`;
- `Limite indisponível`;
- a explicação de degradação aplicável, se houver.

O nome e o identificador da via expiram junto com a localização, conforme a
regra existente de dez segundos.

## Tratamento de erros

- Resposta Overpass vazia: estado de via não confirmada, sem classificá-la como
  falha de rede.
- Via sem nome e sem referência: pode fornecer limite, mas não exibe uma linha
  vazia de via atual.
- `maxspeed` condicional, variável, por faixa ou não numérico: via permanece
  identificada e o limite fica indisponível.
- Falha de uma instância: tenta a próxima conforme a política de failover.
- Falha de todas as instâncias: preserva a última via enquanto a localização
  estiver válida e apresenta indisponibilidade online.
- Rumo ausente: usa a regra conservadora por distância; não transforma o caso
  automaticamente em baixa precisão de posição.

## Testes

### Unidade

- consulta inclui vias sem `maxspeed`;
- `RoadMatch` aceita limite nulo;
- via bidirecional é pareada nos dois sentidos;
- via curva usa o segmento local;
- via sem limite conserva nome ou `ref`;
- rumo ausente aceita candidato inequívoco e rejeita candidatos ambíguos;
- incerteza da velocidade não bloqueia o nome da via;
- precisão horizontal acima dos limites produz o estado correto;
- failover ocorre apenas para as classes de falha previstas;
- resposta vazia não abre circuito nem aparece como erro de rede.

### Controlador e interface

- via aparece com limite indisponível;
- alertas de limite não são emitidos quando o limite é nulo;
- troca de via exige duas amostras;
- estados de posição, velocidade, rumo, pareamento e rede não se confundem;
- via expira após dez segundos sem localização válida.

### Integração

- resposta Overpass com via nomeada sem `maxspeed`;
- primeira instância falha e a segunda responde;
- resposta com `maxspeed` válido mantém o comportamento atual de limite e
  anúncio.

## Critérios de aceitação

1. Uma via nomeada sem `maxspeed` aparece no painel.
2. Uma via bidirecional pode ser identificada nos dois sentidos.
3. A via pode ser identificada parado quando houver um candidato inequívoco.
4. Baixa precisão da velocidade não impede a exibição da via.
5. Falha de uma instância Overpass não impede a consulta quando a segunda está
   disponível.
6. Os testes existentes continuam passando e os novos cenários ficam cobertos.
