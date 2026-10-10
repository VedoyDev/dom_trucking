# dom_trucking — Manual

Job de entrega de caixas em equipe: monte uma equipe com o NPC, leve as caixas por uma sequência de lojas sorteadas e devolva o caminhão para todos receberem o pagamento.

---

## Sumário

1. [Dependências](#dependências)
2. [Instalação](#instalação)
3. [Configuração](#configuração)
4. [Fluxo do job](#fluxo-do-job)
5. [Segurança](#segurança)
6. [Idiomas](#idiomas)
7. [Estrutura de arquivos](#estrutura-de-arquivos)

---

## Dependências

| Recurso | Obrigatório | Observação |
|---|---|---|
| `ox_lib` | Sim | `lib.zones`, `lib.notify`, `lib.showTextUI`, `lib.callback` |
| `ox_target` | Sim | Alvos no NPC, no caminhão e no ponto de entrega (ou um recurso compatível, como `mri_Qinteract`) |
| `ox_inventory` | Sim | Pagamento via `AddItem` no servidor |
| `mri_Qcarkeys` | Não | Se estiver iniciado, o líder recebe a chave do caminhão |

Requer **OneSync** (o servidor valida a posição dos jogadores e do caminhão). Não usa banco de dados.

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
3. Garanta que o item definido em `Config.Reward.Reward` (padrão `money`) exista no `ox_inventory`.

---

## Configuração

Todas as opções ficam em `config.lua`.

### Geral

| Campo | Descrição |
|---|---|
| `Config.Language` | Idioma dos textos (`pt-br` ou `en`, arquivos em `locales/`) |
| `Config.Debug` | Mostra no console por que o caminhão ou uma caixa foram recusados |

### NPC, caminhão e caixa

| Campo | Descrição |
|---|---|
| `Config.NPC.Model` / `Location` / `Heading` | Ped que gerencia a equipe |
| `Config.NPC.Zone` | Área (`Coords`, `Size`, `Rotation`) em que o NPC é criado/removido |
| `Config.Truck.Model` / `Location` / `Heading` | Caminhão gerado para o líder ao iniciar a rota |
| `Config.Box.Model` | Prop da caixa carregada |

### Entregas

| Campo | Descrição |
|---|---|
| `Config.DropOff.Points` | Lista de pontos de entrega (`vec3`). A caixa é entregue exatamente nesse ponto |
| `Config.DropOff.ZoneRadius` | Raio em volta do ponto que conta como "chegou na loja" e libera pegar caixa no caminhão |
| `Config.DropOff.BoxesMin` / `BoxesMax` | Caixas sorteadas por entrega |
| `Config.DropOff.RoutesMin` / `RoutesMax` | Entregas sorteadas por rota (limitado ao número de pontos) |

Para adicionar uma loja basta incluir mais um `vec3` em `Config.DropOff.Points`.

### Equipe e pagamento

| Campo | Descrição |
|---|---|
| `Config.Group.MaxMembers` | Máximo de jogadores por equipe |
| `Config.Group.BoxesMultiplierPerExtraPlayer` | Aumento de caixas por jogador extra (0.30 = +30%) |
| `Config.Group.RoutesPerExtraPlayer` | Entregas extras por jogador extra (arredondado para cima) |
| `Config.Group.PayMultiplierPerExtraPlayer` | Aumento do pagamento por jogador extra |
| `Config.Reward.Reward` | Item do `ox_inventory` pago a cada membro |
| `Config.Reward.AmountMin` / `AmountMax` | Valor base sorteado |

### Interface

| Campo | Descrição |
|---|---|
| `Config.Notify.Position` / `Duration` | Posição e duração das notificações |
| `Config.Hud.Enabled` / `Position` | HUD fixo (`lib.showTextUI`) com o progresso da rota |

### Segurança

| Campo | Descrição |
|---|---|
| `Config.Security.ActionCooldown` | Tempo mínimo (ms) entre pegar/entregar caixas |
| `Config.Security.GrabDistance` | Distância máxima do jogador até o caminhão para pegar caixa |
| `Config.Security.StoreDistance` | Distância máxima do jogador até a loja para pegar caixa (mantenha maior que `ZoneRadius`) |
| `Config.Security.DropDistance` | Distância máxima até o ponto de entrega |
| `Config.Security.ReturnDistance` | Distância máxima do caminhão e do líder até o NPC para finalizar |
| `Config.Security.SpawnDistance` | Distância máxima do caminhão registrado até o ponto de spawn |

---

## Fluxo do job

1. No NPC, um jogador escolhe **Criar equipe** e vira líder. O HUD mostra o ID dele.
2. Os outros escolhem **Entrar em equipe** e digitam o **ID do líder**.
3. O líder escolhe **Iniciar rota**. O servidor sorteia todas as lojas da rota de uma vez, sem repetir, e o caminhão é gerado.
4. O GPS marca a primeira loja. Ao chegar no raio da loja, qualquer membro pode **Pegar caixa** nas portas traseiras do caminhão e **Entregar caixa** no ponto da loja.
5. Ao entregar todas as caixas, a próxima loja da sequência é marcada. O HUD mostra `Caixas x/y | Entrega x/y`.
6. Ao concluir a última entrega, o GPS marca o NPC. O líder leva o caminhão e escolhe **Devolver caminhão**. Todos os membros recebem o pagamento.

Se o líder sair da equipe ou do servidor, a equipe é encerrada e o caminhão é removido.

---

## Segurança

Toda a lógica que vale dinheiro roda no servidor:

- Pegar e entregar caixa são `lib.callback` validados (distância do caminhão, da loja e do ponto de entrega, se o jogador está carregando caixa, limite de caixas da entrega e cooldown).
- O caminhão registrado precisa ter o modelo configurado e ter surgido no ponto de spawn.
- O pagamento exige rota concluída, caminhão e líder perto do NPC, e só acontece uma vez.

---

## Idiomas

Os textos ficam em `locales/<idioma>.json` e são carregados por `shared/language.lua` conforme `Config.Language`. Para traduzir, copie `locales/en.json` com outro nome e ajuste `Config.Language`.

---

## Estrutura de arquivos

```
dom_trucking/
├── client.lua          — NPC, zonas, HUD, caminhão do líder, pegar/entregar caixa
├── server.lua          — equipes, sorteio da rota, validações e pagamento
├── config.lua          — todas as opções
├── shared/language.lua — carregamento dos locales
├── locales/            — textos (pt-br, en)
└── fxmanifest.lua
```
