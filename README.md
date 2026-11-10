# Rutina

Agendador automático de refeições do Restaurante Universitário (RU) da Universidade Federal de Santa Maria (UFSM), escrito em Zig.

É uma reescrita do `ruina`, que deixou de funcionar.

## Como funciona

A cada execução, o Rutina:

1. lê a sua matrícula e senha (argumentos, variáveis de ambiente ou prompt);
2. lê o `config.json` com os seus horários da semana;
3. descobre qual é o **dia seguinte** (no horário de Brasília, UTC−3);
4. se houver refeições configuradas para esse dia, entra no Portal da UFSM e agenda cada uma delas.

Se o programa não encontrar nada configurado para o dia seguinte, ele termina sem fazer login.

**Regra da sexta-feira:** com `use_monday_schedule_on_friday` ligado, na sexta o Rutina agenda as refeições de **segunda-feira**, desde que o `config.json` não tenha nenhum item de sábado ou domingo. Se tiver, ele agenda o sábado normalmente.

Se algum agendamento falhar, o programa continua com os demais e termina com código de saída `1`, o que facilita o uso em scripts e no `cron`.

## Requisitos

- Linux (o prompt de senha escondida usa chamadas específicas do Linux)
- Zig >= 0.18.0-dev.861+1a0778dc2

## Compilação

```sh
git clone https://github.com/Garccez/rutina
cd rutina
zig build -Doptimize=ReleaseSmall
```

O executável fica em `./zig-out/bin/rutina`.

## Configuração

O Rutina procura um arquivo `config.json` na **pasta de onde ele é executado**. Exemplo:

```json
{
	"environment": {
		"app": "UFSMDigital",
		"device_info": "Apple iPhone ios:15.7.3",
		"message_token": "SEU-TOKEN-AQUI"
	},
	"behaviour": {
		"use_monday_schedule_on_friday": false
	},
	"schedules": [
		{
			"weekday": "mon",
			"restaurant": 1,
			"coffee": true,
			"lunch": true,
			"dinner": true
		},
		{
			"weekday": "tue",
			"restaurant": 2,
			"lunch": true,
			"vegetarian": true
		}
	]
}
```

<!-- TODO: explicar de onde vêm os valores de app, device_info e message_token -->

| Campo | Descrição |
|---|---|
| `weekday` | Dia da semana: `mon`, `tue`, `wed`, `thu`, `fri`, `sat` ou `sun` |
| `restaurant` | `1` ou `2`. O RU 1 serve café, almoço e janta; o RU 2 serve apenas almoço e funciona como desafogamento do RU 1 |
| `coffee`, `lunch`, `dinner` | Quais refeições agendar (opcionais, o padrão é `false`) |
| `vegetarian` | Opção vegetariana (opcional, o padrão é `false`) |

Você pode ter vários itens para o mesmo dia (por exemplo, um para cada RU). Nesse caso, o Rutina os agenda em sequência, com uma pausa de 3 segundos entre eles.

## Uso

A **matrícula** é obrigatória. A **senha** pode vir de três lugares, nesta ordem de prioridade: opção `-p`, variável de ambiente ou prompt no terminal.

```sh
# Recomendado: informa só a matrícula e digita a senha no prompt (ela não aparece na tela)
./zig-out/bin/rutina -u MATRICULA

# Com variáveis de ambiente
export RUTINA_USERNAME=MATRICULA
export RUTINA_PASSWORD=SENHA
./zig-out/bin/rutina
```

| Opção | Descrição |
|---|---|
| `-u`, `--username` | Matrícula (ou use `RUTINA_USERNAME`) |
| `-p`, `--password` | Senha (ou use `RUTINA_PASSWORD`). **Evite:** a senha fica visível na lista de processos |

## Automatizando com cron

Para agendar todo dia sem digitar nada, guarde as credenciais num arquivo que só você consiga ler:

```sh
# ~/.rutina.env  (depois: chmod 600 ~/.rutina.env)
export RUTINA_USERNAME=MATRICULA
export RUTINA_PASSWORD=SENHA
```

E adicione uma linha ao `crontab -e`, ajustando o horário e o caminho:

```
0 20 * * * cd ~/rutina && . ~/.rutina.env && ./zig-out/bin/rutina
```

O `cd` é necessário para o programa encontrar o `config.json`.

## Privacidade e segurança

- Nada é salvo pelo programa nem enviado para ninguém além do Portal da UFSM.
- O `config.json` contém o `message_token`. **Não o publique** nem o envie para um repositório: se você usa Git, coloque-o no `.gitignore`.
- O `.gitignore` também deve incluir `zig-out/` e `.zig-cache/`.

## Testes

```sh
zig build test
```
