# dom_trucking — Manual

Job de entrega de caixas: pegue o caminhão com um NPC, leve as caixas até uma loja sorteada e devolva o veículo para receber o pagamento.

---

## Sumário

1. [Dependências](#dependências)
2. [Instalação](#instalação)
3. [Configuração](#configuração)
4. [Fluxo do job](#fluxo-do-job)
5. [Entrypoints para outros recursos](#entrypoints-para-outros-recursos)
6. [Estrutura de arquivos](#estrutura-de-arquivos)

---

## Dependências

| Recurso | Obrigatório | Observação |
|---|---|---|
| `ox_lib` | Sim | `lib.zones`, `lib.notify`, `lib.requestModel` |
| `ox_target` | Sim | Alvos no NPC, no caminhão e no ponto de entrega |
| `ox_inventory` | Sim | Entrega da recompensa via `AddItem` no servidor |

O recurso não usa framework (QBox/ESX) nem banco de dados.

---

## Instalação

1. Copie a pasta `dom_trucking` para `resources/`.
2. Adicione ao `server.cfg`, **depois** das dependências:
   ```
   ensure ox_lib
   ensure ox_target
   ensure ox_inventory
   ensure dom_trucking
   ```
3. Garanta que o item definido em `Config.Reward.Reward` (padrão `money`) exista no `ox_inventory`. Com o padrão `money` não é necessária nenhuma configuração extra.

Não há SQL para importar.

---

## Configuração

Todas as opções ficam em `config.lua`.

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `Config.NPC.Location` | vec3 | Sim | Onde o NPC que entrega o job é criado |
| `Config.NPC.Heading` | number | Sim | Rotação do NPC |
| `Config.Truck.Location` | vec3 | Sim | Onde o caminhão (`boxville2`) é gerado ao aceitar o job |
| `Config.Truck.Heading` | number | Sim | Rotação do caminhão |
| `Config.DropOff.Location` | tabela de vec3 | Sim | Lojas de entrega. Uma é sorteada por job; o centro da zona de detecção |
| `Config.DropOff.TargetPoint` | tabela de vec3 | Sim | Ponto exato de largar a caixa em cada loja. O índice **deve** corresponder ao mesmo índice de `Location` |
| `Config.DropOff.BoxesMin` | number | Sim | Mínimo de caixas sorteadas por entrega |
| `Config.DropOff.BoxesMax` | number | Sim | Máximo de caixas sorteadas por entrega |
| `Config.Reward.Reward` | string | Sim | Nome do item do `ox_inventory` pago ao final |
| `Config.Reward.AmountMin` | number | Sim | Quantidade mínima paga (sorteada) |
| `Config.Reward.AmountMax` | number | Sim | Quantidade máxima paga (sorteada) |
| `Config.Notification.InJob` | tabela `lib.notify` | Sim | Aviso ao tentar pegar um job já em andamento |
| `Config.Notification.HasBox` | tabela `lib.notify` | Sim | Aviso ao tentar pegar uma caixa já estando com uma |
| `Config.Notification.NoBox` | tabela `lib.notify` | Sim | Aviso ao tentar largar sem estar com caixa |
| `Config.Notification.ReturnTruck` | tabela `lib.notify` | Sim | Aviso quando todas as caixas foram entregues |
| `Config.Notification.CompletedJob` | tabela `lib.notify` | Sim | Aviso ao devolver o caminhão e receber o pagamento |

Cada tabela de `Config.Notification` aceita os campos do `lib.notify`: `title`, `description`, `type` e `position`.

### Adicionar uma nova loja

Adicione a coordenada da zona em `Config.DropOff.Location` e o ponto de largar caixa em `Config.DropOff.TargetPoint`, **na mesma posição da lista**:

```lua
Config.DropOff = {
    Location = {
        vec3(376.299, 322.467, 103.437),   -- loja 1
        vec3(1159.387, -325.542, 69.205),  -- loja 2
    },
    TargetPoint = {
        vec3(375.514, 334.839, 103.566),   -- ponto de largar da loja 1
        vec3(1163.135, -313.367, 69.205),  -- ponto de largar da loja 2
    },
    ...
}
```

---

## Fluxo do job

1. Ao entrar na zona do NPC (fixa em `vec3(65.692, 117.731, 79.159)` no `client.lua`), o ped `s_m_m_postal_02` é criado em `Config.NPC.Location`.
2. Alvo **Get a job** no NPC: gera o caminhão `boxville2` em `Config.Truck.Location`, sorteia uma loja de `Config.DropOff.Location` e cria a rota no GPS.
3. Ao chegar na loja, o blip da rota some e são criados dois alvos: **Grab Box** na porta traseira direita do caminhão (bone `door_dside_r`) e **Dropoff Box** no `TargetPoint` da loja.
4. Cada caixa é uma prop `prop_cs_cardbox_01` anexada ao ped, com a animação `anim@heists@box_carry@`. O número de caixas é sorteado entre `BoxesMin` e `BoxesMax`.
5. Entregue todas as caixas e o GPS cria a rota de volta para o NPC.
6. Alvo **Return Truck** no caminhão: deleta o veículo, dispara `dom_trucking:Reward` e o servidor credita entre `AmountMin` e `AmountMax` do item de recompensa.

---

## Entrypoints para outros recursos

### Evento de servidor `dom_trucking:Reward`

Disparado pelo cliente ao devolver o caminhão. Credita ao `source` uma quantidade aleatória entre `Config.Reward.AmountMin` e `Config.Reward.AmountMax` do item `Config.Reward.Reward`.

```lua
TriggerServerEvent('dom_trucking:Reward')
```

> O evento não valida se o job foi realmente concluído.

### Eventos de cliente

| Evento | Efeito |
|---|---|
| `dom_trucking:removeZone` | Remove a zona de detecção da loja atual |
| `dom_trucking:removeStoreZones` | Remove os alvos de caixa e marca o job como concluído, criando a rota de volta ao NPC |

Ambos são internos do fluxo do job e não foram feitos para uso externo.

---

## Estrutura de arquivos

```
dom_trucking/
├── client.lua       — zonas, NPC, caminhão, alvos de pegar/largar caixa e devolução
├── server.lua       — evento dom_trucking:Reward, pagamento via ox_inventory
├── config.lua       — coordenadas, quantidade de caixas, recompensa e notificações
├── README.md
└── fxmanifest.lua
```
