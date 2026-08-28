# Autopsia: AWS S3 (us-east1) (28/02/2017)
**Autor:** Lucas Oliveira Rodrigues (@luskation)
**Fonte primaria:** https://aws.amazon.com/pt/message/41926/
**Data de acesso:** 28/08/2026
## 1. O que aconteceu

Início: 09:37. Um funcionário da Amazon tentou desligar poucos servidores lentos para manutenção, mas digitou um comando errado que acabou desligando computadores essenciais por engano. Detecção: 09:45. Esses computadores sabiam onde cada arquivo da nuvem estava guardado. Com eles desligados, a internet não conseguia achar dados, travando milhares de serviços famosos. Restauração: 13:54. Para consertar, a Amazon precisou reiniciar esse catálogo gigante do zero e checar item por item, o que demorou horas para carregar por causa do volume gigantesco de informações.

## 2. Qual das Tres Vias falhou

Aprendizado. A Terceira via é sobre treinar e testar falhas antes que elas aconteçam no mundo real. Como a equipe passou anos sem ensaiar uma reinicialização completa para ver como o sistema se comportaria com a internet muito maior, ninguém sabia de verdade quanto tempo o serviço levaria para voltar. O time só foi descobrir os limites do próprio sistema em produção.

## 3. Quais metricas DORA teriam denunciado antes

Possivelmente duas métricas: Taxa de falha em mudanças e tempo médio de restauração. Um engenheiro digitar um comando simples e toda a aplicação cair, sem nenhum aviso ou trava de segurança é hediondo. Para completar, a AWS, há anos, não reiniciava aquele sistema do zero na maior região deles. A internet cresceu absurdamente e o time continuava achando que o sistema voltaria rápido como no passado. 

## 4. Qual pratica do semestre teria evitado -- e em que semana

Semana 10 - Kubernetes I: modelo declarativo. No modelo declarativo, ninguém entra no servidor para apagar algo na mão, igual o engenheiro fez. Você só avisa o sistema como quer que as coisas fiquem. 

## 5. A cultura do relatorio: generativa ou patologica?

Em vez de colocar o dedo na cara e culpar a pessoa que errou a digitação, a AWS assumiu o erro como uma falha das próprias ferramentas e dos processos da empresa, focando 100% em aprender e melhorar a segurança do sistema. É notório no seguinte trecho: 

"While removal of capacity is a key operational practice, in this instance, the tool used allowed too much capacity to be removed too quickly. We have modified this tool to remove capacity more slowly and added safeguards to prevent capacity from being removed when it will take any subsystem below its minimum required capacity level."
