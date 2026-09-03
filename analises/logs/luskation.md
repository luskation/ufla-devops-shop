# Analise de access.log -- Lucas Oliveira Rodrigues (@luskation)
**Linhas analisadas:** 516866

## 1. Volume e falha

```bash
echo "== total =="
wc -l < dados/access.log

echo "== 4xx =="
awk '$9 ~ /^4/' dados/access.log | wc -l

echo "== 5xx =="
awk '$9 ~ /^5/' dados/access.log | wc -l

echo "== percentuais =="
awk '{ total++; if ($9 ~ /^4/) q4++; else if ($9 ~ /^5/) q5++ }
     END { printf "4xx: %d (%.3f%%)\n5xx: %d (%.3f%%)\ntotal: %d\n", q4, q4/total*100, q5, q5/total*100, total }' \
     dados/access.log
```

```
total: 516866
4xx: 6162 (1.192%)
5xx: 11749 (2.273%)
```

**Leitura:** O log tem 516.866 requisicoes. 6.162 falharam com 4xx (1,19%) e 11.749 com 5xx (2,27%) os erros de servidor sao quase o dobro dos erros de cliente, o que ja sugere que o problema principal esta no backend, nao em quem esta pedindo errado.

## 2. Os 10 IPs mais frequentes

```bash
awk '{print $1}' dados/access.log | sort | uniq -c | sort -rn | head -10
```

```
  88400 203.0.113.47
   1788 192.0.2.245
   1772 192.0.2.171
   1771 192.0.2.81
   1771 192.0.2.225
   1771 192.0.2.16
   1767 192.0.2.138
   1762 192.0.2.222
   1757 192.0.2.45
   1753 192.0.2.166
```

**Leitura:** O IP 203.0.113.47 e disparado o mais frequente: 88.400 requisicoes, contra ~1.750-1.790 dos demais, quase 50x mais que o segundo colocado. Isso sozinho ja seria estranho, mas o que confirma que e suspeito, e nao so "e o que aparece mais", e o padrao de comportamento:

```bash
echo "== caminhos pedidos pelo IP =="
awk '$1=="203.0.113.47"{print $7}' dados/access.log | sort | uniq -c | sort -rn

echo "== user-agent do IP =="
awk -F'"' '$1 ~ /^203\.0\.113\.47 /{print $6}' dados/access.log | sort | uniq -c

echo "== status codes do IP =="
awk '$1=="203.0.113.47"{print $9}' dados/access.log | sort | uniq -c

echo "== ritmo: requisicoes por minuto (amostra) =="
awk '$1=="203.0.113.47"{print $4}' dados/access.log | cut -d: -f1-3 | sort | uniq -c | sort -rn | head -5
```

```
== caminhos pedidos pelo IP ==
  22224 /api/busca?q=mochila
  22161 /api/busca?q=tenis
  22090 /api/busca?q=camiseta
  21925 /api/busca?q=fone

== user-agent do IP ==
  88400 curl/8.5.0

== status codes do IP ==
  81500 200
   6900 503

== ritmo: requisicoes por minuto (amostra) ==
   1021 [14/Aug/2026:23:44
   1017 [14/Aug/2026:23:00
   1015 [14/Aug/2026:23:32
   1007 [14/Aug/2026:23:21
   1002 [14/Aug/2026:23:17
```

**Leitura:** 203.0.113.47 so pede /api/busca com quatro termos fixos, sempre com curl/8.5.0 (nenhum navegador real, nenhuma outra rota, nenhum asset estatico como CSS/JS/favicon) e num ritmo de ~1.000 requisicoes por minuto (~17/s), sustentado por quase uma hora.

## 3. O endpoint quebrado

```bash
echo "== paths com mais 500 =="
awk '$9==500{print $7}' dados/access.log | sort | uniq -c | sort -rn | head -5

echo "== total de requisicoes e total de 500 do pior path =="
awk '$7=="/api/relatorio/gerar"{print $9}' dados/access.log | sort | uniq -c
awk '$7=="/api/relatorio/gerar"' dados/access.log | wc -l
```

```
== paths com mais 500 ==
   3620 /api/relatorio/gerar
    228 /
    167 /api/produtos
    160 /produtos
    150 /produtos/detalhe

== total de requisicoes e total de 500 do pior path ==
   6780 200
   3620 500
10400
```

**Leitura:** /api/relatorio/gerar concentra 3.620 dos 4.849 erros 500 do log (~75% de todos os 500). Olhando so para esse caminho: de 10.400 requisicoes, 3.620 falharam com 500. Nao quebra sempre (a maioria, 65%, retorna 200), mas falha com frequencia alta demais para ser acaso; parece um bug ou limite de recurso (timeout, memoria, dependencia externa) que se manifesta em ~1 a cada 3 chamadas.

## 4. A hora do pico

```bash
awk -F: '{print $2}' dados/access.log | sort -n | uniq -c
```

```
   3262 00
   1967 01
   1810 02
   1471 03
   1498 04
   1844 05
   3904 06
   9759 07
  19519 08
  27621 09
  30869 10
  32526 11
  31895 12
  29952 13
  31225 14
  32529 15
  30886 16
  28575 17
  25996 18
  22807 19
  18860 20
  15577 21
  43979 22
  68535 23
```

**Leitura:** Olhando so o numero bruto, a hora 23h vence disparado (68.535 requisicoes). Mas essa hora coincide exatamente com a janela de atividade do bot 203.0.113.47

```bash
awk '$1!="203.0.113.47"' dados/access.log | awk -F: '{print $2}' | sort -n | uniq -c
```

```
   ...
   15577 21
   13039 22
   11075 23
```

**Leitura:** Sem o bot, as horas 22h e 23h caem para ~13.000 e ~11.000. O trafego organico real tem um pico suave em torno de 11h-15h (30.800 a 32.500 requisicoes/hora), compativel com horario comercial/uso diurno da loja. Ou seja: o "pico" aparente de 23h e artefato do bot, nao de uso real. Outra evidencia de que 203.0.113.47 distorce qualquer leitura do log se nao for isolado.

## 5. Alguem batendo na porta

```bash
echo "== total de tentativas a caminhos sensiveis =="
awk 'tolower($7) ~ /admin|\.env|\.git|wp-login|phpmyadmin/' dados/access.log | wc -l

echo "== por caminho =="
awk 'tolower($7) ~ /admin|\.env|\.git|wp-login|phpmyadmin/{print $7}' dados/access.log | sort | uniq -c | sort -rn

echo "== IPs distintos e contagem por IP =="
awk 'tolower($7) ~ /admin|\.env|\.git|wp-login|phpmyadmin/{print $1}' dados/access.log | sort | uniq -c | sort -rn
awk 'tolower($7) ~ /admin|\.env|\.git|wp-login|phpmyadmin/{print $1}' dados/access.log | sort -u | wc -l

echo "== o que o servidor respondeu =="
awk 'tolower($7) ~ /admin|\.env|\.git|wp-login|phpmyadmin/{print $9}' dados/access.log | sort | uniq -c
```

```
== total ==
2080

== por caminho ==
    382 /admin/login
    368 /wp-login.php
    356 /.git/config
    343 /.env
    318 /phpmyadmin/index.php
    313 /admin

== IPs ==
   1053 198.51.100.9
   1027 198.51.100.23
2 IPs distintos

== respostas ==
   2080 404
```

**Leitura:** 2.080 tentativas vindas de so 2 IPs (198.51.100.9 e 198.51.100.23). Nenhum dos dois usa navegador, os dois falam python-requests/2.32.3, ou seja, e script, nao gente clicando e os dois agem de madrugada, entre 02h e 05h, passando pela lista classica de quem esta procurando porta aberta: /admin, /admin/login, /wp-login.php, /.git/config, /.env e /phpmyadmin/index.php. E o comportamento de um scanner automatizado de vulnerabilidades, o tipo de varredura que roda o tempo todo contra qualquer IP publico na internet. A boa noticia e que nenhuma dessas portas existe: o servidor respondeu 404 nas 2.080 tentativas, sem excecao.

## Conclusao: minha primeira acao como operador de plantao

Se eu estivesse de plantao nesta madrugada, minha primeira acao seria bloquear o IP 203.0.113.47 no WAF/firewall e nao investigar os scanners de /admin primeiro. Motivo: os scanners batem em rotas que nem existem e recebem 404. Ja o 203.0.113.47 e a causa direta e comprovada dos 6.900 erros 503 (100% deles), derrubando a disponibilidade do servico para os outros ~430 IPs legitimos que estavam navegando normalmente no mesmo periodo. Bloquear esse IP resolve o incidente de disponibilidade imediatamente; so depois disso eu abriria um chamado para o time de backend sobre /api/relatorio/gerar, que falha em ~35% das chamadas mesmo sem ataque nenhum.
